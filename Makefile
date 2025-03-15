###############################################################################
# Variables
###############################################################################

# Default values
PROJECT_NAME      := infra
ORG               ?= unifyops
REGION            ?= us-east-1
INFRA_ENV         ?= dev

TF_DIR                  := tf
TF_STATE_KEY            := ${PROJECT_NAME}/terraform_state.tfstate
TF_STATE_BUCKET         ?= ${ORG}-tfstate-bucket
TF_STATE_REGION         ?= $(REGION)
TF_STATE_DYNAMODB_TABLE ?= ${ORG}-tfstate-lock
TF_VARS_FILE            := secrets.tfvars
AWS_PROFILE             ?= dev
TF_COMMAND              := AWS_PROFILE=$(AWS_PROFILE) terraform -chdir=$(TF_DIR)

TF_VARS := \
  -var="org=$(ORG)" \
  -var="region=$(REGION)" \
  -var="project_name=$(PROJECT_NAME)" \
  -var="infra_env=$(INFRA_ENV)" \
  -var-file="secrets.tfvars"

BACKEND_TF_VARS   := \
  --backend-config="bucket=$(TF_STATE_BUCKET)" \
  --backend-config="key=$(TF_STATE_KEY)" \
  --backend-config="region=$(REGION)" \
  --backend-config="dynamodb_table=$(TF_STATE_DYNAMODB_TABLE)" \
  --backend-config="encrypt=true"

# Combine commonly used Terraform arguments into a single variable
TF_COMMON_ARGS := $(TF_VARS) $(ARGS)

############################################################################### 
# Targets
###############################################################################

.PHONY: init validate fmt plan apply destroy list clean help

# Default goal
.DEFAULT_GOAL := help

init: ## Initialize Terraform, install providers
	$(TF_COMMAND) init $(TF_COMMON_ARGS) $(BACKEND_TF_VARS)

validate: ## Validate Terraform files
	$(TF_COMMAND) validate $(TF_COMMON_ARGS)

fmt: ## Format Terraform files
	$(TF_COMMAND) fmt -recursive

plan: ## Plan Terraform changes
	$(TF_COMMAND) plan $(TF_COMMON_ARGS)

apply: ## Apply Terraform changes
	$(TF_COMMAND) apply $(TF_COMMON_ARGS)

destroy: ## Destroy Terraform-managed infrastructure
	$(TF_COMMAND) destroy $(TF_COMMON_ARGS)

list: ## List Terraform resources
	$(TF_COMMAND) state list

clean: ## Remove all generated files
	rm -f $(TF_PLAN_FILE)

help: ## Display this help message
	@echo "Usage:"
	@echo "  make <target> [INFRA_ENV=<INFRA_ENV>] [ORG=<org>] [REGION=<region>]"
	@echo
	@echo "Targets:"
	@awk 'BEGIN {FS = ":.*?##"} /^[a-zA-Z_-]+:.*?##/ \
		{ printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)