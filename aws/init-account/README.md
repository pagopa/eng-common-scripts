# init-account

Inizialize account with following operations:
1. create bucket for app terraform state with lifecycle rule to delete noncurrent versions (naming convention `terraform-state<randomstring>`)
2. create DynamoDB table for infrastructure terraform lock (naming convention `terraform-lock`)

```sh
./create-terraform-state.sh PROFILE-NAME
```
