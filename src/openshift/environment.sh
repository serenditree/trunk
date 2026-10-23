########################################################################################################################
# Environment
########################################################################################################################
[[ -f ~/.config/serenditree/ocp.env ]] && source ~/.config/serenditree/ocp.env

EXOSCALE_API_KEY="$(pass exoscale/dev@exoscale.com.access)"
EXOSCALE_API_SECRET="$(pass exoscale/dev@exoscale.com.secret)"
EXOSCALE_ACCOUNT=$_ST_ACCOUNT
export EXOSCALE_API_KEY EXOSCALE_API_SECRET EXOSCALE_ACCOUNT

TF_VAR_api_key="$EXOSCALE_API_KEY"
TF_VAR_api_secret="$EXOSCALE_API_SECRET"
export TF_VAR_api_key TF_VAR_api_secret

_API_CIDR="$(dig +short myip.opendns.com @resolver1.opendns.com)/32"
export _API_CIDR
