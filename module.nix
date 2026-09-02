# nivis-aws-form-action — an altcha-protected HTML-form backend as a nivis
# module: Go Lambda (upstream altcha-lib-go + SES send) behind an API Gateway v2
# HTTP API (GET /challenge, POST /submit), with least-privilege IAM.
#
# Module conventions (nivis has no module scoping yet — see nivis bean
# nixform2-l2hx):
#   - `namePrefix` namespaces every resource name (nivis ids are a flat
#     `provider.type.name` space). The default "" keeps the canonical names —
#     use a non-empty prefix when instantiating this module more than once per
#     domain.
#   - The module references the provider id "aws"; the consumer supplies that
#     provider (and the backend) in its own toIR.
#   - The Lambda artifact is passed IN (cfg.lambdaZip): build it with this
#     repo's `lib.mkLambdaZip pkgs` (preferably the consumer's own nixpkgs, for
#     toolchain identity) or use `packages.<system>.lambda-zip`.
#
# Prerequisites (not managed here): a verified SES identity for cfg.ses.from,
# and an SSM SecureString parameter at cfg.hmacParam (the altcha HMAC key) —
# read by the Lambda at runtime, never present in state.
{
  nivis,
  namePrefix ? "",
  cfg,
}:
let
  inherit (nivis) mkResource str;

  n = s: if namePrefix == "" then s else "${namePrefix}_${s}";

  lambdaRole = mkResource {
    provider = "aws";
    type = "aws_iam_role";
    name = n "altcha_lambda";
    config = {
      name = "${cfg.baseName}-altcha";
      assume_role_policy = builtins.toJSON {
        Version = "2012-10-17";
        Statement = [
          {
            Effect = "Allow";
            Action = "sts:AssumeRole";
            Principal.Service = "lambda.amazonaws.com";
          }
        ];
      };
      tags = cfg.tags;
    };
  };

  lambdaPolicy = mkResource {
    provider = "aws";
    type = "aws_iam_role_policy";
    name = n "altcha_lambda";
    config = {
      name = "altcha-lambda";
      role = lambdaRole.refAttr "id";
      policy = builtins.toJSON {
        Version = "2012-10-17";
        Statement = [
          {
            Sid = "Logs";
            Effect = "Allow";
            Action = [
              "logs:CreateLogGroup"
              "logs:CreateLogStream"
              "logs:PutLogEvents"
            ];
            Resource = "arn:aws:logs:*:*:*";
          }
          {
            Sid = "SendMail";
            Effect = "Allow";
            Action = [
              "ses:SendEmail"
              "ses:SendRawEmail"
            ];
            Resource = "*";
          }
          {
            Sid = "ReadHmacParam";
            Effect = "Allow";
            Action = "ssm:GetParameter";
            Resource = "arn:aws:ssm:${cfg.region}:${cfg.account}:parameter${cfg.hmacParam}";
          }
          {
            Sid = "DecryptHmacParam";
            Effect = "Allow";
            Action = "kms:Decrypt";
            # Scoped to SSM's use; tighten to the specific key ARN if a CMK is
            # adopted for the parameter.
            Resource = "*";
            Condition."StringEquals"."kms:ViaService" = "ssm.${cfg.region}.amazonaws.com";
          }
        ];
      };
    };
  };

  lambda = mkResource {
    provider = "aws";
    type = "aws_lambda_function";
    name = n "altcha";
    config = {
      function_name = "${cfg.baseName}-altcha";
      role = lambdaRole.refAttr "arn";
      runtime = "provided.al2023";
      handler = "bootstrap";
      architectures = [ "x86_64" ];
      # The zip is built during eval (the readFile below forces it); a plain
      # store-path string is both plan- and apply-safe (a drvFile __build leaf
      # breaks `nivis plan` for in-state resources). A code change -> new store
      # path + hash -> redeploy.
      filename = "${cfg.lambdaZip}/function.zip";
      source_code_hash = builtins.readFile "${cfg.lambdaZip}/function.zip.base64sha256";
      timeout = cfg.timeout or 10;
      memory_size = cfg.memorySize or 128;
      environment = [
        {
          variables = {
            ALTCHA_HMAC_PARAM = cfg.hmacParam;
            SES_FROM = cfg.ses.from;
            SES_TO = cfg.ses.to;
            ALLOWED_ORIGIN = cfg.ses.allowedOrigin;
          };
        }
      ];
      tags = cfg.tags;
    };
  };

  api = mkResource {
    provider = "aws";
    type = "aws_apigatewayv2_api";
    name = n "form";
    config = {
      name = "${cfg.baseName}-form";
      protocol_type = "HTTP";
      cors_configuration = [
        {
          allow_origins = [ cfg.ses.allowedOrigin ];
          allow_methods = [ "GET" "POST" "OPTIONS" ];
          allow_headers = [ "content-type" ];
        }
      ];
      tags = cfg.tags;
    };
  };

  integration = mkResource {
    provider = "aws";
    type = "aws_apigatewayv2_integration";
    name = n "lambda";
    config = {
      api_id = api.refAttr "id";
      integration_type = "AWS_PROXY";
      integration_uri = lambda.refAttr "invoke_arn";
      integration_method = "POST";
      payload_format_version = "2.0";
    };
  };

  routeChallenge = mkResource {
    provider = "aws";
    type = "aws_apigatewayv2_route";
    name = n "challenge";
    config = {
      api_id = api.refAttr "id";
      route_key = "GET /challenge";
      target = str [ "integrations/" (integration.refAttr "id") ];
    };
  };

  routeSubmit = mkResource {
    provider = "aws";
    type = "aws_apigatewayv2_route";
    name = n "submit";
    config = {
      api_id = api.refAttr "id";
      route_key = "POST /submit";
      target = str [ "integrations/" (integration.refAttr "id") ];
    };
  };

  stage = mkResource {
    provider = "aws";
    type = "aws_apigatewayv2_stage";
    name = n "default";
    config = {
      api_id = api.refAttr "id";
      name = "$default";
      auto_deploy = true;
    };
  };

  apiPermission = mkResource {
    provider = "aws";
    type = "aws_lambda_permission";
    name = n "apigw";
    config = {
      statement_id = "AllowAPIGatewayInvoke";
      action = "lambda:InvokeFunction";
      function_name = lambda.refAttr "function_name";
      principal = "apigateway.amazonaws.com";
      source_arn = str [ (api.refAttr "execution_arn") "/*/*" ];
    };
  };
in
{
  resources = [
    lambdaRole
    lambdaPolicy
    lambda
    api
    integration
    routeChallenge
    routeSubmit
    stage
    apiPermission
  ];

  # For consumer wiring (e.g. an Amplify same-origin rewrite proxy).
  apiEndpointRef = api.refAttr "api_endpoint";

  outputs = {
    api_endpoint = api.refAttr "api_endpoint";
    challenge_url = str [ (api.refAttr "api_endpoint") "/challenge" ];
    submit_url = str [ (api.refAttr "api_endpoint") "/submit" ];
  };
}
