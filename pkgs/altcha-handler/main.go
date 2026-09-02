// altcha-handler is the technative.eu v2026 contact-form Lambda.
//
// It runs on the AWS `provided.al2023` custom runtime behind an API Gateway v2
// HTTP API with two routes:
//
//	GET  /challenge  -> issue a fresh altcha challenge
//	POST /submit     -> verify the altcha solution, then send the form via SES
//
// The altcha proof-of-work / HMAC logic is delegated entirely to the upstream
// github.com/altcha-org/altcha-lib-go library — nothing is reimplemented here.
//
// The HMAC key is read from SSM Parameter Store at cold start (never baked into
// the environment or the deployment package); only the parameter NAME is passed
// in via ALTCHA_HMAC_PARAM.
package main

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net/url"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/sesv2"
	sestypes "github.com/aws/aws-sdk-go-v2/service/sesv2/types"
	"github.com/aws/aws-sdk-go-v2/service/ssm"

	altcha "github.com/altcha-org/altcha-lib-go"
)

var (
	initOnce    sync.Once
	initErr     error
	hmacKey     string
	sesClient   *sesv2.Client
	fromAddr    string
	toAddr      string
	allowOrigin string
)

// bootstrap loads the HMAC key from SSM and the SES client. Runs once per
// execution environment (cold start), cached for warm invocations.
func bootstrap(ctx context.Context) error {
	cfg, err := config.LoadDefaultConfig(ctx)
	if err != nil {
		return fmt.Errorf("load aws config: %w", err)
	}

	paramName := os.Getenv("ALTCHA_HMAC_PARAM")
	if paramName == "" {
		return fmt.Errorf("ALTCHA_HMAC_PARAM not set")
	}
	out, err := ssm.NewFromConfig(cfg).GetParameter(ctx, &ssm.GetParameterInput{
		Name:           aws.String(paramName),
		WithDecryption: aws.Bool(true),
	})
	if err != nil {
		return fmt.Errorf("get hmac parameter: %w", err)
	}
	hmacKey = aws.ToString(out.Parameter.Value)

	sesClient = sesv2.NewFromConfig(cfg)
	fromAddr = os.Getenv("SES_FROM")
	toAddr = os.Getenv("SES_TO")
	allowOrigin = os.Getenv("ALLOWED_ORIGIN")
	return nil
}

func ensureInit(ctx context.Context) error {
	initOnce.Do(func() { initErr = bootstrap(ctx) })
	return initErr
}

func resp(status int, contentType, body string) events.APIGatewayV2HTTPResponse {
	return events.APIGatewayV2HTTPResponse{
		StatusCode: status,
		Headers: map[string]string{
			"Content-Type":                 contentType,
			"Access-Control-Allow-Origin":  allowOrigin,
			"Access-Control-Allow-Methods": "GET,POST,OPTIONS",
			"Access-Control-Allow-Headers": "content-type",
			// Never cacheable: responses may transit Amplify's CDN via the
			// /sendform/* rewrite proxy, and a cached challenge would be
			// stale/replayed for every visitor.
			"Cache-Control": "no-store",
		},
		Body: body,
	}
}

func handler(ctx context.Context, req events.APIGatewayV2HTTPRequest) (events.APIGatewayV2HTTPResponse, error) {
	if err := ensureInit(ctx); err != nil {
		return resp(500, "application/json", `{"error":"initialization failed"}`), nil
	}

	method := req.RequestContext.HTTP.Method
	path := req.RawPath
	switch {
	case method == "OPTIONS":
		return resp(204, "text/plain", ""), nil
	case method == "GET" && strings.HasSuffix(path, "/challenge"):
		return handleChallenge()
	case method == "POST" && strings.HasSuffix(path, "/submit"):
		return handleSubmit(ctx, req)
	default:
		return resp(404, "application/json", `{"error":"not found"}`), nil
	}
}

func handleChallenge() (events.APIGatewayV2HTTPResponse, error) {
	// Expiry bounds replay: VerifySolution(checkExpires=true) only enforces an
	// expiry if the challenge carries one — without it, solved payloads replay
	// forever. Replay WITHIN the window is an accepted trade-off (contact form).
	expires := time.Now().Add(10 * time.Minute)
	ch, err := altcha.CreateChallenge(altcha.ChallengeOptions{
		HMACKey:   hmacKey,
		MaxNumber: 100000,
		Expires:   &expires,
	})
	if err != nil {
		return resp(500, "application/json", `{"error":"challenge failed"}`), nil
	}
	b, err := json.Marshal(ch)
	if err != nil {
		return resp(500, "application/json", `{"error":"encode failed"}`), nil
	}
	return resp(200, "application/json", string(b)), nil
}

func handleSubmit(ctx context.Context, req events.APIGatewayV2HTTPRequest) (events.APIGatewayV2HTTPResponse, error) {
	body := req.Body
	if req.IsBase64Encoded {
		dec, err := base64.StdEncoding.DecodeString(body)
		if err != nil {
			return resp(400, "application/json", `{"error":"bad body"}`), nil
		}
		body = string(dec)
	}

	form, err := url.ParseQuery(body)
	if err != nil {
		return resp(400, "application/json", `{"error":"bad form encoding"}`), nil
	}

	payload := form.Get("altcha")
	if payload == "" {
		return resp(400, "application/json", `{"error":"missing altcha solution"}`), nil
	}

	// Upstream verification (checkExpires = true rejects stale challenges).
	ok, err := altcha.VerifySolution(payload, hmacKey, true)
	if err != nil || !ok {
		return resp(403, "application/json", `{"error":"invalid altcha solution"}`), nil
	}

	if err := sendEmail(ctx, form); err != nil {
		return resp(502, "application/json", `{"error":"delivery failed"}`), nil
	}
	return resp(200, "application/json", `{"ok":true}`), nil
}

func sendEmail(ctx context.Context, form url.Values) error {
	var sb strings.Builder
	for k, vs := range form {
		if k == "altcha" {
			continue
		}
		for _, v := range vs {
			fmt.Fprintf(&sb, "%s: %s\n", k, v)
		}
	}

	subject := form.Get("subject")
	if subject == "" {
		subject = "Contact form technative.eu"
	}

	_, err := sesClient.SendEmail(ctx, &sesv2.SendEmailInput{
		FromEmailAddress: aws.String(fromAddr),
		Destination:      &sestypes.Destination{ToAddresses: []string{toAddr}},
		Content: &sestypes.EmailContent{
			Simple: &sestypes.Message{
				Subject: &sestypes.Content{Data: aws.String(subject)},
				Body: &sestypes.Body{
					Text: &sestypes.Content{Data: aws.String(sb.String())},
				},
			},
		},
	})
	return err
}

func main() {
	lambda.Start(handler)
}
