#!/usr/bin/env bash
# One-time, idempotent setup of GitHub Actions -> AWS authentication (OIDC, no long-lived keys).
#
# Creates per environment a read-only IAM role `tabz-<env>-github-plan` that only the GitHub environment
# `<env>-plan` of this repository can assume. CI uses it for `terragrunt plan`.
#
# Kept as a script rather than a Terragrunt unit on purpose: it is the trust anchor CI itself depends on
# (chicken-and-egg), and it is run once by a human with admin credentials.
#
# Usage: AWS_PROFILE=<admin profile> ./bootstrap/github-oidc.sh [env ...]   (default: dev prod)
set -euo pipefail

REPO="petricbranko/tabz-task"
# The repo uses GitHub's immutable OIDC subject: owner and repo are pinned by numeric ID, so a re-created
# account/repo with the same name can never assume these roles.
#   gh api repos/petricbranko/tabz-task/actions/oidc/customization/sub --jq .sub_claim_prefix
SUB_PREFIX="repo:petricbranko@54512375/tabz-task@1438809153"
PROJECT="tabz"
REGION="eu-central-1"
[ $# -eq 0 ] && set -- dev prod
ENVS=("$@")

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
PROVIDER_URL="token.actions.githubusercontent.com"
PROVIDER_ARN="arn:aws:iam::${ACCOUNT_ID}:oidc-provider/${PROVIDER_URL}"

# The OIDC provider is account-wide and may already be used by other repositories: create it if missing,
# never modify it.
if aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$PROVIDER_ARN" >/dev/null 2>&1; then
  echo "OIDC provider exists: $PROVIDER_ARN"
else
  aws iam create-open-id-connect-provider --url "https://${PROVIDER_URL}" --client-id-list sts.amazonaws.com >/dev/null
  echo "OIDC provider created: $PROVIDER_ARN"
fi

for env in "${ENVS[@]}"; do
  role="${PROJECT}-${env}-github-plan"

  # Only jobs that run in the GitHub environment `<env>-plan` of this repo get a matching `sub` claim.
  # Fork PRs never receive an OIDC token.
  trust=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Federated": "${PROVIDER_ARN}" },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "${PROVIDER_URL}:aud": "sts.amazonaws.com",
        "${PROVIDER_URL}:sub": "${SUB_PREFIX}:environment:${env}-plan"
      }
    }
  }]
}
EOF
)

  # `plan` refreshes every resource. ReadOnlyAccess covers the Describe/Get/List calls and reading state;
  # refreshing the Redis secret version additionally needs the secret value (it is in state anyway).
  # CI plans run with -lock=false, so the role needs no write access at all.
  extra=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ReadAppSecrets",
      "Effect": "Allow",
      "Action": "secretsmanager:GetSecretValue",
      "Resource": "arn:aws:secretsmanager:${REGION}:${ACCOUNT_ID}:secret:${PROJECT}-${env}/*"
    },
    {
      "Sid": "DecryptAppSecretsViaSecretsManager",
      "Effect": "Allow",
      "Action": "kms:Decrypt",
      "Resource": "*",
      "Condition": { "StringEquals": { "kms:ViaService": "secretsmanager.${REGION}.amazonaws.com" } }
    }
  ]
}
EOF
)

  if aws iam get-role --role-name "$role" >/dev/null 2>&1; then
    aws iam update-assume-role-policy --role-name "$role" --policy-document "$trust"
    echo "Role updated: $role"
  else
    aws iam create-role --role-name "$role" \
      --description "GitHub Actions read-only plan role for ${PROJECT} ${env} (${REPO})" \
      --assume-role-policy-document "$trust" \
      --tags Key=Project,Value="$PROJECT" Key=Environment,Value="$env" Key=ManagedBy,Value=bootstrap >/dev/null
    echo "Role created: $role"
  fi

  aws iam attach-role-policy --role-name "$role" --policy-arn arn:aws:iam::aws:policy/ReadOnlyAccess
  aws iam put-role-policy --role-name "$role" --policy-name plan-extra --policy-document "$extra"

  echo "  -> GitHub repository variable AWS_PLAN_ROLE_ARN_$(echo "$env" | tr '[:lower:]' '[:upper:]') = arn:aws:iam::${ACCOUNT_ID}:role/${role}"
done
