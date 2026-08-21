# AWS Tagging beyond key-values: ABAC authorization demo

## Resumo

Este repositório demonstra **ABAC (Attribute-Based Access Control)** na AWS usando tags como atributo de decisão, em vez do modelo tradicional de uma role/policy por recurso ou por time. Uma única IAM Role, confiável por toda a organização do GitHub via OIDC, só consegue sincronizar arquivos para um bucket S3 quando a tag `Application` do bucket bate com o nome do repositório que está chamando — a autorização nasce da comparação entre um atributo do token (`sub`) e um atributo do recurso (tag), não de uma lista fixa de permissões por repositório. O repo também traz uma SCP que garante que todo bucket S3 criado na conta carregue o conjunto mínimo de tags (`CostCenter`, `Team`, `Application`, `Environment`), e um pipeline de GitHub Actions que serve como demo funcional de ponta a ponta.

## Como funciona

1. O GitHub Actions do repositório assume a IAM Role via **OIDC** (`sts:AssumeRoleWithWebIdentity`), sem credenciais de longa duração.
2. A trust policy da Role confia em qualquer repositório da sua org/usuário do GitHub, definida em `local.github_org` (claim `sub` do token, com wildcard — ver seção abaixo), **e** restringe tanto o `ref` quanto o GitHub Environment aceitos de acordo com o ambiente (`terraform.workspace`) — ver [Restrição de ambiente](#restrição-de-ambiente-por-terraformworkspace) abaixo.
3. A policy de permissão anexada à Role (`s3:PutObject`, `s3:GetObject`, `s3:DeleteObject`, `s3:ListBucket`) só libera acesso a um bucket se **duas** condições baterem ao mesmo tempo, dentro de uma **única** condição `StringLike` na claim `sub`: o nome do repo bater com a tag `Application` do bucket, **e** o sufixo `:environment:<nome>` do próprio `sub` bater com a tag `Environment` do bucket — ambas usando [policy variables](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_variables.html) (`${aws:ResourceTag/Application}` / `${aws:ResourceTag/Environment}`). Ver [Ambiente embutido no sub](#ambiente-embutido-no-sub-sem-session-tags) abaixo para o porquê desse formato.
4. O bucket (`my-demo-bucket/`) tem [ABAC habilitado a nível de bucket](https://docs.aws.amazon.com/AmazonS3/latest/userguide/buckets-tagging-enable-abac.html) (`aws_s3_bucket_abac`), necessário para que `aws:ResourceTag` seja avaliado em ações de bucket como `ListBucket`.
5. Um conjunto de tags (`CostCenter`, `Team`, `Application`, `Environment`) é o "contrato" de atributos usado tanto pela Role quanto pela SCP de guardrail (`abac/scp.tf`), que nega a criação de buckets sem essas tags.

### Formato da claim `sub` do GitHub

O GitHub adicionou IDs numéricos imutáveis ao claim `sub` (ex.: `repo:sua-org@7799231/seu-repo@1335473687:...`), além do formato antigo (`repo:sua-org/seu-repo:...`). O wildcard na condição (`repo:${github_org}*/*`) cobre os dois formatos sem duplicar policies — veja [Available keys for AWS OIDC federation](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_iam-condition-keys.html#condition-keys-wif).

> **Pegadinha:** o *sufixo* da claim `sub` muda de acordo com o job. Se o job **não** declara `environment:`, o sufixo é `:ref:refs/heads/<branch>` (ou `:ref:refs/tags/<tag>`). Se o job **declara** `environment: <nome>` (como todos os jobs deste repo declaram), o sufixo passa a ser `:environment:<nome>` **em vez de** `:ref:...` — os dois nunca aparecem juntos no mesmo `sub`. A trust policy (`abac/role.tf`) usa `sub` só para o match de org/repo (`repo:${github_org}*/*`, sem sufixo) e casa `ref` como condição independente (claim separada do `sub`, ver [ref só na trust policy](#ref-só-na-trust-policy) abaixo); já a policy de permissão (`abac/policies.tf`) faz o oposto — usa esse sufixo `:environment:<nome>` de propósito, para casar o ambiente sem session tags (ver [Ambiente embutido no sub](#ambiente-embutido-no-sub-sem-session-tags) abaixo).

### Restrição de ambiente por `terraform.workspace`

Além do match org/repo, a trust policy da Role (`abac/role.tf`, `local.allowed_refs` / `local.allowed_environment` em `abac/locals.tf`) restringe **qual `ref`** (branch ou tag) **e qual GitHub Environment** podem assumir a Role, com base no workspace do Terraform (`terraform.workspace`) — sem precisar de nenhuma variável extra, já que o ambiente é decidido pelo próprio workspace usado no `apply`:

| Workspace | `local.is_production` | Refs aceitos (`ref`) | Environment aceito (`environment`) |
| --- | --- | --- | --- |
| `production` | `true` | Somente **tags** git — `refs/tags/*` (ex.: releases `v1.2.3`) | `production` |
| qualquer outro (`default`, `staging`, `dev`, ...) | `false` | Somente **push/branch** `main` ou `master` | `default` |

Ou seja:

- **Em produção**, só um `ref` de tag (`refs/tags/*`) rodando no GitHub Environment `production` consegue fazer `AssumeRoleWithWebIdentity` — um push direto em `main`, ou uma tag rodando em outro Environment, é rejeitado na trust policy, antes mesmo de chegar na policy ABAC de tags do bucket. Isso força o deploy em produção a passar por um processo de release (criar uma tag) através do Environment certo.
- **Fora de produção**, só um `ref` de branch `main` ou `master` rodando no Environment `default` consegue assumir a Role — pushes em outras branches, tags, ou o Environment errado são rejeitados. Isso mantém os ambientes de não-produção atrelados à branch principal, sem abrir para qualquer branch de feature.

Essas restrições de `ref` e `environment` são somadas (`AND`, já que todas as condições estão na mesma statement) à condição de `sub` (org/repo) e `aud` já existentes — elas não substituem, e não interferem, na condição ABAC de tags (`aws:ResourceTag/Application`) que continua controlando o acesso por repositório em `abac/policies.tf`.

Para trocar de workspace localmente:

```sh
cd abac
terraform workspace new production   # ou: terraform workspace select production
mise exec -- terraform plan
```

> Nenhum outro recurso muda de comportamento com o workspace hoje além dessa condição de `ref` — as tags `Environment` (em `abac/locals.tf` e `my-demo-bucket/locals.tf`) já usavam `terraform.workspace` antes desta mudança.

### `ref` só na trust policy

`ref` (e toda claim do GitHub OIDC exceto `sub`) tem **"Available in session: No"** na tabela oficial da AWS ([Available keys for AWS OIDC federation](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_iam-condition-keys.html#condition-keys-wif)) — ou seja, só existe no request context da própria chamada `AssumeRoleWithWebIdentity`. Uma vez que a Role é assumida, as chamadas seguintes (`s3:PutObject`, `s3:ListBucket`, etc.) **não** carregam mais `token.actions.githubusercontent.com:ref` no contexto — só `sub` sobrevive na sessão. Por isso a restrição de branch/tag (`refs/heads/main`, `refs/tags/*`) só pode ser feita na trust policy da Role (`abac/role.tf`), no único momento em que essa claim existe:

```hcl
condition {
  test     = "StringLike"
  variable = "${local.github_oidc_domain}:ref"
  values   = local.allowed_refs
}
```

- No workflow deste repo (`.github/workflows/deploy.yml`), isso é implementado com dois jobs: `sync-non-production` (push em `main`) e `sync-production` (push de tag `v*`).
- [GitHub Environments](https://docs.github.com/en/actions/deployment/targeting-different-environments/using-environments-for-deployment) também podem ter suas próprias proteções (reviewers obrigatórios, branches/tags permitidas, secrets por ambiente) configuráveis em **Settings → Environments** no repositório — uma camada adicional de controle no lado do GitHub, complementar (não substitui) às condições abaixo.

### Ambiente embutido no `sub` (sem session tags)

A claim `environment`, isolada, também **não é session-available** — então uma condição `StringEquals` comparando `token.actions.githubusercontent.com:environment` direto numa policy de recurso (como `abac/policies.tf`) nunca funcionaria: a chave simplesmente não existe fora da chamada `AssumeRoleWithWebIdentity`, e `StringEquals` com chave ausente sempre avalia como falso. Isso já causou um bug real neste repo: uma versão anterior tinha exatamente essa condição em `abac/policies.tf`, e **todo `s3 sync` era negado**, independente de qualquer tag estar certa.

A saída natural para "levar o ambiente para dentro da sessão" seria [session tags](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_session-tags.html) (`aws:PrincipalTag/...`, que É session-available) — mas `AssumeRoleWithWebIdentity` **não aceita o parâmetro `Tags`/`TransitiveTagKeys`** da API do STS; esse recurso só existe em `AssumeRole` (encadeamento de roles IAM-para-IAM). Tags de sessão para identidades federadas só podem vir de claims dentro do próprio JWT, e o OIDC do GitHub não permite adicionar claims customizadas — então essa rota exigiria uma segunda Role e um hop extra de `AssumeRole` só para propagar a tag.

Em vez disso, este repo aproveita algo que já é verdade sobre a claim `sub`: quando o job declara `environment: <nome>` (todo job deste workflow declara), o **sufixo** do `sub` passa a ser `:environment:<nome>` em vez de `:ref:refs/heads/<branch>` — os dois nunca aparecem juntos (ver CloudTrail abaixo). Como `sub` **é** session-available, dá para casar repo **e** ambiente numa única condição `StringLike`, com dois policy variables no mesmo padrão:

```hcl
condition {
  test     = "StringLike"
  variable = "${local.github_oidc_domain}:sub"
  values   = ["repo:${local.github_org}*/$${aws:ResourceTag/Application}*:environment:$${aws:ResourceTag/Environment}"]
}
```

Exemplo real de `sub` visto no CloudTrail deste projeto:

```
repo:lays147@7799231/aws-abac-tagging@1335473687:environment:default
```

Isso significa:

- O padrão exige, na mesma string, que o repo bata com `Application` **e** que o sufixo `environment:<nome>` bata com a tag `Environment` do bucket — sem precisar de session tags nem de uma segunda Role.
- **Fail closed por construção**: se o job que está chamando `aws s3 sync` não declarar `environment:` (sufixo `:ref:...` em vez de `:environment:...`), o padrão nunca bate e a chamada é negada — não existe um caminho onde a ausência do `environment:` no job vira um "sempre permite". Isso só é seguro porque todo job deste workflow declara `environment:`; um workflow que não declarasse perderia esse enforcement (voltaria a só checar o repo, como antes desta mudança).
- Essa condição substitui completamente a antiga condição `StringEquals` na claim `environment` isolada, que nunca funcionou.

## Ativando a SCP (`scp_target_id`)

Os recursos da SCP em `abac/scp.tf` (`aws_organizations_policy.require_tags`) são sempre criados, mas só ficam **anexados** a algo se a variável `scp_target_id` (definida em `abac/variables.tf`) for preenchida — por padrão ela é `""` e o `aws_organizations_policy_attachment` nem é criado (`count = 0`). Isso só funciona se a conta AWS for a **management account** de uma [AWS Organization](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_getting-started_concepts.html); em conta standalone, deixe a variável vazia mesmo.

Para descobrir o ID do root ou de uma OU e aplicar:

```sh
# ID do root da organização
aws organizations list-roots --query "Roots[0].Id" --output text
# ex.: r-abc1

# (opcional) IDs de OUs específicas dentro do root
aws organizations list-organizational-units-for-parent \
  --parent-id r-abc1 --query "OrganizationalUnits[].{Id:Id,Name:Name}"
```

Depois, aplique passando o ID (root ou OU) via `-var`:

```sh
cd abac
mise exec -- terraform apply -var="scp_target_id=r-abc1"
```

Ou, para deixar fixo no repositório, crie `abac/terraform.tfvars` (já ignorado pelo `.gitignore`):

```hcl
scp_target_id = "r-abc1"
```

## Arquitetura

```mermaid
flowchart LR
    subgraph GH["GitHub"]
        WF["GitHub Actions\nsync-non-production (push main, env default)\nsync-production (push tag v*, env production)"]
    end

    subgraph AWS["Conta AWS"]
        OIDC["OIDC Provider\ntoken.actions.githubusercontent.com"]
        ROLE["IAM Role\ngithub-actions-assume-role\n(confia em repo:sua-org*/*,\nref e environment restritos por workspace,\ncondições independentes do sub)"]
        POLICY["Policy s3-sync\nsub == repo.../${aws:ResourceTag/Application}*:environment:${aws:ResourceTag/Environment}\n(ambiente embutido no sufixo do sub)"]
        BUCKET["S3 Bucket\naws-abac-tagging-bucket\nTag Application=aws-abac-tagging\nTag Environment=terraform.workspace\nABAC habilitado"]
        SCP["SCP require-tags\n(nega criação sem\nCostCenter/Team/Application/Environment)"]
    end

    WF -- "1. AssumeRoleWithWebIdentity\n(token OIDC, claims sub+ref+environment)" --> OIDC
    OIDC -- "2. valida aud + sub + ref + environment" --> ROLE
    ROLE -- "3. credenciais temporárias\n(sessão só carrega sub)" --> WF
    WF -- "4. aws s3 sync" --> POLICY
    POLICY -- "5. compara sub vs tag Application\ne vs tag Environment (via sufixo do sub)" --> BUCKET
    SCP -.-> BUCKET
```

## Estrutura do repositório

| Caminho | Conteúdo |
| --- | --- |
| `abac/` | OIDC provider (data source), IAM Role genérica, policy ABAC de sync S3, SCP de tags obrigatórias |
| `my-demo-bucket/` | Bucket S3 do demo, tags, bloqueio de acesso público, ABAC habilitado |
| `.github/workflows/deploy.yml` | Pipeline: assume role via OIDC + `aws s3 sync` |
| `Makefile` | `make fmt` / `make validate` / `make plan` via [mise](https://mise.jdx.dev/) |

## Roteiro de teste

Passo a passo para validar a SCP de tags obrigatórias e o ABAC de sync na prática. Pressupõe que `scp_target_id` já foi configurado (seção acima), que `vars.ASSUME_ROLE_ARN` está definida no repositório do GitHub (Settings → Secrets and variables → Actions → Variables), e que os **GitHub Environments** `default` e `production` existem no repositório (Settings → Environments → New environment) — sem eles, a claim `environment` não é emitida no token OIDC, o sufixo do `sub` vira `:ref:...` em vez de `:environment:...`, e tanto o `AssumeRoleWithWebIdentity` (trust policy) quanto o `s3 sync` (policy de permissão) são negados (ver [ref só na trust policy](#ref-só-na-trust-policy) e [Ambiente embutido no sub](#ambiente-embutido-no-sub-sem-session-tags)).

### 1. Fazer um fork do repositório

Faça um fork deste repositório para a sua própria conta/organização do GitHub. Depois, ajuste `github_org` em `abac/locals.tf` para o nome da sua org/usuário no GitHub (o valor usado na trust policy da Role):

```hcl
github_org = "seu-usuario-ou-org"
```

E configure a variável `ASSUME_ROLE_ARN` no seu fork (Settings → Secrets and variables → Actions → Variables) com o ARN da Role que será criada no próximo passo — ela só existe depois do primeiro `terraform apply`, então pode deixar um valor provisório e atualizar depois.

### 2. Criar os recursos do `abac/`

```sh
cd abac
mise exec -- terraform apply -var="scp_target_id=<root-ou-ou-id-da-sua-organization>"
```

Isso cria a IAM Role, a policy ABAC de sync e anexa a SCP `require-tags` ao root da Organization — a partir daqui, **qualquer** conta dentro dela é bloqueada de criar bucket S3 sem as quatro tags.

### 3. Tentar criar o bucket sem uma tag (deve falhar)

Em `my-demo-bucket/locals.tf`, comente uma tag qualquer, por exemplo `CostCenter`:

```hcl
tags = {
  # CostCenter  = "payments"
  Team        = "pix"
  Application = "aws-abac-tagging"
  Environment = terraform.workspace
}
```

Aplique:

```sh
cd ../my-demo-bucket
mise exec -- terraform apply
```

O `apply` deve falhar com `AccessDenied` na chamada `CreateBucket`, algo como:

```
Error: creating S3 Bucket: operation error S3: CreateBucket, https response error
StatusCode: 403, ... AccessDenied: ... with an explicit deny in a service control policy
```

Isso confirma que a SCP está ativa e bloqueando a criação de recursos sem o conjunto completo de tags do ABAC.

### 4. Corrigir e criar o bucket

Descomente a tag e aplique de novo:

```hcl
tags = {
  CostCenter  = "payments"
  Team        = "pix"
  Application = "aws-abac-tagging"
  Environment = terraform.workspace
}
```

```sh
mise exec -- terraform apply
```

Agora o `apply` deve passar — bucket criado com as quatro tags, ABAC habilitado e acesso público bloqueado.

### 5. Fazer o deploy

O workflow (`.github/workflows/deploy.yml`) tem dois jobs, cada um casando com o workspace usado para criar o bucket:

- Se o bucket foi criado no workspace `default` (`terraform.workspace` = `default`, o padrão), dê `push` na branch `main` do seu fork. Isso dispara o job `sync-non-production` (`environment: default`, `ref` = `refs/heads/main`).
- Se o bucket foi criado no workspace `production` (`terraform workspace select production` antes do `apply` em `abac/` e `my-demo-bucket/`), crie e dê push numa tag `v*`, por exemplo `git tag v0.1.0 && git push origin v0.1.0`. Isso dispara o job `sync-production` (`environment: production`, `ref` = `refs/tags/*`).

Em ambos os casos, o job deve completar com sucesso: o `ref` e o GitHub Environment do job batem com o que a trust policy exige (ver [ref só na trust policy](#ref-só-na-trust-policy)), então a Role é assumida via OIDC; a sincronização em si funciona porque o `sub` do token (`repo:sua-org/aws-abac-tagging...:environment:<nome>`) bate ao mesmo tempo com a tag `Application` **e** com a tag `Environment` do bucket na policy de permissão (ver [Ambiente embutido no sub](#ambiente-embutido-no-sub-sem-session-tags)).

### 6. Editar a tag `Application` no console (deve quebrar o próximo deploy)

No console AWS: **S3 → aws-abac-tagging-bucket → Properties → Tags**, mude o valor de `Application` para algo diferente do nome do repositório, por exemplo `outro-valor`.

Dispare o pipeline de novo (novo `push` em `main`/tag `v*`, ou re-run do workflow) **sem alterar o Terraform**. O passo `aws s3 sync` deve falhar com:

```
fatal error: An error occurred (AccessDenied) when calling the ListObjectsV2 operation: Access Denied
```

Isso acontece porque a condição `StringLike` da policy (`sub` do token vs. `${aws:ResourceTag/Application}`) não bate mais — a tag do bucket não corresponde ao repositório que está chamando, então o ABAC nega o acesso mesmo a Role sendo assumida com sucesso.

O mesmo tipo de falha acontece se você mudar a tag `Environment` do bucket para um valor que não bate com o GitHub Environment do job (`default`/`production`) — o sufixo `:environment:<nome>` do `sub` deixa de bater com `${aws:ResourceTag/Environment}` no padrão `StringLike`, negando o acesso mesmo com a tag `Application` correta. Repare que isso só afeta o `s3 sync` (policy de permissão) — mudar a tag `Environment` do bucket **não** afeta o `AssumeRoleWithWebIdentity` em si, porque a trust policy (`abac/role.tf`) não conhece tags de bucket nenhum; ela decide com base só na claim `environment` do job comparada a um valor fixo (`local.allowed_environment`, derivado do `terraform.workspace`), não com base em nenhum recurso S3.

> Para reverter, basta rodar `terraform apply` em `my-demo-bucket/` de novo — o Terraform detecta o drift na tag e a restaura, já que ela é gerenciada via `local.tags`.

## Referências

- [IAM and AWS STS condition context keys — Available keys for AWS OIDC federation](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_iam-condition-keys.html#condition-keys-wif)
- [IAM policy elements: Variables and tags](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_variables.html)
- [Configuring a role for GitHub OIDC identity provider](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_create_for-idp_oidc.html#idp_oidc_Create_GitHub)
- [Enabling ABAC for S3 buckets (PutBucketAbac)](https://docs.aws.amazon.com/AmazonS3/latest/userguide/buckets-tagging-enable-abac.html)
- [SCPs — Example: Require a tag on create requests](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_scps_examples_tagging.html)
- [aws-actions/configure-aws-credentials](https://github.com/aws-actions/configure-aws-credentials)

## Rodando localmente

```sh
make validate   # terraform init + validate em abac/ e my-demo-bucket/
make plan       # terraform plan em ambos (precisa de credenciais AWS)
```
