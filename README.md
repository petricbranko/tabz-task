# tabz-task

A containerized web app on ECS Fargate, managed with Terragrunt, in two environments: **dev** and **prod**.

The app is plain nginx. The task says the app itself doesn't matter, so I spent the time on the platform around
it: networking, a secret from Secrets Manager, a Redis replication group the app can provably reach, autoscaling,
and real differences between dev and prod.

The task only asks for a plan. I did plan it, but I also applied both environments in my own AWS account,
checked that everything works, and destroyed them again. A plan proves the code is valid; it doesn't prove nginx
actually comes up behind the load balancer, or that the container can really talk to Redis. Section
[How I tested it](#how-i-tested-it) has the details.

- [What's in here](#whats-in-here)
- [How to read this repo](#how-to-read-this-repo)
- [How to run it](#how-to-run-it)
- [How it works](#how-it-works)
- [Decisions and trade-offs](#decisions-and-trade-offs)
- [What I'd add with more time](#what-id-add-with-more-time)
- [How I tested it](#how-i-tested-it)

---

## What's in here

| The task asked for | Where it is |
|---|---|
| Plan-ready, backend configured | `environments/root.hcl`: S3 state with native locking. The state bucket is created on the first run. CI plans both environments on every push. |
| One reusable ecs-service module | `modules/ecs-service`. dev and prod use it, each with different inputs. |
| App reads one secret from Secrets Manager | The Redis auth token. ECS injects it into the container as `REDIS_AUTH_TOKEN`. See [The secret](#the-secret). |
| App connects to a Redis replication group, and why it works | `modules/redis`, plus a small sidecar that pings Redis every 30 seconds. See [Why the app can reach Redis](#why-the-app-can-reach-redis). |
| Autoscaling, with a reason | Scales on requests per task, with CPU as a backup. See [Autoscaling](#autoscaling). |
| Prod different from dev | 3 AZs vs 2, HA Redis, on-demand base capacity, VPC endpoints, flow logs, and more. See [Dev vs prod](#dev-vs-prod). |
| README | You're reading it. |

---

## How to read this repo

If you have ten minutes, read in this order:

1. **`environments/dev/eu-central-1/services/web/terragrunt.hcl`**. This is the whole service definition for
   dev: image, size, Spot, autoscaling and the night schedule. Then open the prod version of the same file next to it.
2. **`environments/_envcommon/ecs-service.hcl`**. This is how the service gets wired to the VPC, the load balancer,
   Redis and the secret. The Redis probe sidecar is defined here too.
3. **`modules/ecs-service/main.tf`**. The reusable module. Its README has a table of what it adds on top of the
   official ECS module.
4. **`environments/root.hcl`**. State backend, provider and tags, shared by every unit.

The commit history is meant to be read as well. I built this step by step: VPC first, then cluster and load
balancer, then the service, Redis, autoscaling, CI and prod. Every step was applied and checked in AWS before
it was committed.

### Layout

```
environments/
  root.hcl                  state backend + provider + tags, included by every unit
  common.hcl                project name + pinned versions of the official modules
  _envcommon/               the shared config of each component (what is the same in dev and prod)
    vpc.hcl  alb.hcl  ecs-cluster.hcl  kms.hcl  redis.hcl  ecs-service.hcl
  dev/
    env.hcl                 account, CIDR, number of AZs
    eu-central-1/
      region.hcl            region + AZ names
      vpc/  kms/  ecs-cluster/  alb/  redis/  services/web/
  prod/
    env.hcl
    eu-central-1/
      ...same units as dev, plus alb-logs/ and vpc-endpoints/
modules/
  ecs-service/              the reusable Fargate service module
  redis/                    ElastiCache replication group + the secret
bootstrap/
  github-oidc.sh            one-time setup of the IAM roles CI uses (OIDC, no AWS keys)
.github/workflows/          CI: lint, validate, security scan, plan dev and prod
```

Each folder with a `terragrunt.hcl` is one **unit**, with its own state file. A unit's own file only holds
what is different for that environment. Everything shared sits in `_envcommon/`. If you diff
`dev/.../redis/terragrunt.hcl` against `prod/.../redis/terragrunt.hcl`, you see exactly how the two environments
differ, and nothing else.

---

## How to run it

### Tools

The exact versions are in `mise.toml` (Terraform 1.17.1, Terragrunt 1.2.1, tflint, trivy). With
[mise](https://mise.jdx.dev):

```bash
mise install
```

You can also install the tools any other way, as long as the versions match. CI reads the same file.

### Option 1: check everything without an AWS account

```bash
cd environments
TG_BACKEND=local terragrunt run --all validate
```

`TG_BACKEND=local` switches every unit to local state. Dependencies between units fall back to mock values,
so this works without any credentials. CI runs exactly this.

### Option 2: plan in your own AWS account

```bash
export AWS_PROFILE=<your profile>
export AWS_ACCOUNT_ID=<your account id>

cd environments/dev                 # or environments/prod
terragrunt run --all --backend-bootstrap plan
```

- `AWS_ACCOUNT_ID` decides the target account. It defaults to mine. The provider refuses to run against any
  other account (`allowed_account_ids`), so you can't plan or apply into the wrong one by accident.
- `--backend-bootstrap` creates the state bucket `tabz-tfstate-<account>-eu-central-1` on the first run. The
  bucket is versioned and encrypted, with public access blocked. Later runs don't need the flag.
- On an empty account, units that depend on others (for example the service, which needs the VPC) plan
  against mock outputs. This is expected: the real values only exist after an apply.

### Option 3: apply it (optional, costs money)

```bash
cd environments/dev
terragrunt run --all --backend-bootstrap apply
```

Dev takes about 10 minutes and costs roughly $2.5 a day. Most of that is the NAT gateway, the load balancer and
the Redis node. Prod takes about 8 minutes and is far more expensive (three NAT gateways, three Redis nodes,
VPC endpoints in three AZs), so I'd only apply it to try it out and then destroy it.

Once it's up:

```bash
# the load balancer address
cd environments/dev/eu-central-1/alb && terragrunt output dns_name

# the Redis probe: one line every 30 seconds
aws logs tail /aws/ecs/tabz-dev-web/redis-probe --follow
#   redis-probe OK host=master.tabz-dev.xxxxxx.euc1.cache.amazonaws.com
```

Dev also has ECS Exec enabled, so you can open a shell in the running task with `aws ecs execute-command`.

### Destroying

```bash
cd environments/dev
terragrunt run --all destroy
```

Prod is protected on purpose, so destroying it takes two extra steps. The load balancer has deletion
protection, and the access log bucket isn't empty. Turn both off for one run, then destroy:

```bash
cd environments/prod/eu-central-1
(cd alb      && terragrunt apply -- -var=enable_deletion_protection=false)
(cd alb-logs && terragrunt apply -- -var=force_destroy=true)
cd .. && terragrunt run --all destroy
```

### CI

`.github/workflows/terragrunt.yml` runs on every push and pull request:

1. **static**. Formatting, tflint, `validate` of every unit, and a trivy security scan of the modules. No AWS
   access at all.
2. **plan (dev)** and **plan (prod)**. A real `plan` against AWS. GitHub logs in through OIDC, so there are no
   stored AWS keys. Each environment has its own **read-only** IAM role, and that role only trusts a job running
   in the matching GitHub environment (`dev-plan` or `prod-plan`). `bootstrap/github-oidc.sh` creates the roles.
   It's a script on purpose: the roles are what CI itself needs in order to log in, so CI can't create them.

The dev plan currently shows "No changes", because dev is running and matches the code. The prod plan shows
"97 to add", because prod is not deployed.

---

## How it works

```
                 internet
                    |
            [ ALB, public subnets ]          SG: 80 from anywhere; egress only to the service SG
                    |  8080
     [ ECS Fargate tasks, private subnets ]  SG: 8080 from the ALB SG only; egress 443 + 6379 to Redis SG
          |                         |
          | 6379, TLS + AUTH        | 443: ECR, Secrets Manager, CloudWatch Logs
          v                         v       (dev: through the NAT gateway, prod: through VPC endpoints)
 [ Redis, elasticache subnets ]
   SG: 6379 from the service SG only
   route table: local only, no way out of the VPC
```

### Terragrunt structure

- **One unit per component**: vpc, kms, ecs-cluster, alb, redis, services/web. Each has its own state file.
  Small states plan faster, a mistake can only damage one component, and you can see from the folder name what
  a change touches.
- **Dependencies are declared** with `dependency` blocks, so `run --all` applies in the right order
  (VPC, then load balancer and Redis, then the service) and destroys in reverse.
- **Shared config in `_envcommon/`**, environment differences in the unit's own file. dev and prod can't drift
  apart by accident, because everything they share is written exactly once.
- **There's a region folder** (`eu-central-1/`), even though there's only one region today. Adding a second
  region later means copying one folder, without moving any state.
- **Official modules where they exist**. VPC, load balancer, ECS cluster, KMS and S3 come from
  `terraform-aws-modules`, with versions pinned once in `common.hcl`. I only wrote my own code where it
  actually adds something: `modules/ecs-service` and `modules/redis`.

### The ecs-service module

The official ECS service module is generic. Every service on this platform needs the same extra things, so the
wrapper adds them once:

- **Load balancer.** Each service brings its own target group and listener rule to the shared load balancer.
  Adding a service never touches the load balancer unit.
- **Security groups.** The module creates the service's security group, and also writes the matching rule on
  the other side. That means the load balancer's egress to this service, and Redis's ingress from this service.
  Every rule points at a security group, never at an IP range.
- **Secrets.** You list the secrets. The module gives the task's execution role permission to read exactly
  those secrets, and to decrypt them only through Secrets Manager.
- **Hardening.** Private subnets, no public IP, read-only root filesystem. Folders the app has to write to
  (nginx needs `/tmp` and `/var/cache/nginx`) are mounted as temporary volumes. Fargate creates those owned by
  root, so a small init container runs first and makes them writable for the non-root nginx user. I found this
  when nginx crashed on its first deploy.
- **Deployments.** Rolling deploys that keep 100% capacity during the rollout, with a circuit breaker that
  rolls back automatically if new tasks don't become healthy.
- **Autoscaling**, described below.

### The secret

The Redis auth token is the app's one secret.

1. `modules/redis` generates a random token and stores it in Secrets Manager as JSON:
   `{"host", "reader", "port", "tls", "auth_token"}`. The secret is encrypted with the environment's own KMS key.
2. The same token is set as the AUTH token on the Redis replication group.
3. The task definition references a single key from the secret: `valueFrom = "<secret arn>:auth_token::"`.
   When a task starts, ECS fetches the value and passes it to the container as the `REDIS_AUTH_TOKEN`
   environment variable.
4. The task's execution role can read that one secret, and decrypt with that one KMS key, and only when the
   call goes through Secrets Manager. The app itself has no permission to call Secrets Manager.

The secret's value never appears in the task definition, the code or the console. It does appear in Terraform
state, see [trade-offs](#decisions-and-trade-offs).

### Why the app can reach Redis

The task says "no Redis code needed, just show it would connect and explain why". To show it, every task runs a
small sidecar container (`redis-probe`) that runs this every 30 seconds:

```
redis-cli -h $REDIS_HOST -p 6379 --tls -a $REDIS_AUTH_TOKEN PING
```

It logs `redis-probe OK` or `redis-probe FAIL` to CloudWatch. It shares the app's network interface, security
group, subnets and secret, so if the probe gets through, the app's own connection gets through too.

Here's every check a connection has to pass, and why it passes:

| Check | Why it passes |
|---|---|
| **Name resolution** | `REDIS_HOST` is the replication group's primary endpoint. The VPC has DNS turned on, so the name resolves to a private IP inside the VPC. If Redis fails over, the name moves to the new primary, so the app needs no config change. |
| **Routing** | The tasks and Redis are in the same VPC. Traffic between subnets uses the VPC's local route, which every route table has. Redis's subnets have their own route table with *only* that local route, so Redis can't reach the internet, and nothing outside the VPC can reach it. |
| **Task side: security group egress** | The service's security group allows outbound 6379 to the Redis security group only. |
| **Redis side: security group ingress** | The Redis security group is created with no inbound rules at all. The service module adds one rule: 6379 from the service's security group. Nothing else can connect, not even other things in the same VPC. |
| **Network ACLs** | Left at the AWS default (allow everything). The security groups do the real filtering, because they're stateful and point at each other, unlike ACLs, which only understand IP ranges. |
| **TLS** | Redis has encryption in transit set to `required`, so plain-text connections are refused. The client connects with `--tls` and checks the certificate against the system CA bundle. |
| **Authentication** | Redis requires the AUTH token. The client gets it from the secret, as described above. |

Both environments were tested for real. In dev and prod, the probe logged `redis-probe OK` every 30 seconds.

### Autoscaling

nginx serving web traffic isn't really limited by CPU or memory. Its load comes from the number of requests.
Memory stays about flat no matter the traffic, and CPU only climbs once the tasks are already struggling. So
I scale on the thing that actually describes the load:

- **Main rule: requests per task.** The target is 1000 requests per task per minute (the ALB metric
  `ALBRequestCountPerTarget`). When traffic goes up, tasks are added before they're overloaded.
- **Backup rule: CPU.** 70% in dev, 60% in prod. It catches the requests that are expensive rather than
  numerous, where the request count looks fine but the tasks are busy. Whichever rule asks for more tasks wins.
- **Cooldowns:** scale out after 60 seconds, scale in after 300 seconds. Adding capacity fast and removing it
  slowly avoids flapping when traffic comes in bursts.

For a real app I'd keep this structure and tune the numbers with a load test. A CPU-heavy app would make CPU
the main rule. A worker that reads from a queue would scale on queue depth instead.

Per environment:

| | dev | prod |
|---|---|---|
| Tasks (min to max) | 1 to 2 | 3 to 12 |
| Capacity | Fargate Spot only | 3 on-demand tasks as a base, anything above that split 1:1 between on-demand and Spot |
| Schedule | 0 tasks on weekdays 20:00 to 07:00 and all weekend (Europe/Belgrade) | always on |

The prod minimum of 3 means one task in each AZ, so losing an AZ never leaves prod without capacity. The base
runs on on-demand capacity, because Spot capacity can be taken back with two minutes' notice. Spot is only used
for extra capacity at peaks, which is where it saves money without putting availability at risk.

The dev night schedule is honest but small. Spot tasks this size cost almost nothing, so it saves roughly
50 cents a week. The real cost of dev is the NAT gateway, the load balancer and Redis, which run around the
clock. The schedule is mostly there to show the pattern. One side effect: running `apply` at night sets the
task count back to its daytime values, so dev wakes up until the next evening. I think that's what you want,
since you're clearly using it right then.

### Dev vs prod

| | dev | prod | Why |
|---|---|---|---|
| AZs | 2 | 3 | Prod survives losing an AZ and still has spare capacity. Dev uses the minimum the load balancer allows. |
| NAT gateways | 1, shared | 1 per AZ | In prod, an AZ outage doesn't take outbound internet away from the other AZs. |
| VPC endpoints | none | ECR, S3, Secrets Manager, Logs, KMS, SSM | AWS API traffic stays inside AWS. It's cheaper than sending it through NAT, and prod keeps working if NAT has problems. In dev, the endpoints would cost more than they save. |
| VPC flow logs | off | on, 90 days | For investigating security incidents. |
| Redis | 1 × `cache.t4g.micro` | 3 × `cache.r7g.large`, one per AZ, automatic failover, Multi-AZ | If the primary dies, a replica takes over and the endpoint name follows it. In dev, the cache can just be lost. |
| Redis snapshots | none | 7 days | |
| Redis changes | applied immediately | wait for the maintenance window | Nobody gets a surprise restart in prod in the middle of the day. |
| Task size | 0.25 vCPU / 512 MB | 0.5 vCPU / 1 GB | |
| Capacity | Spot only | on-demand base, Spot on top | See [Autoscaling](#autoscaling). |
| Load balancer | no deletion protection | deletion protection, access logs to S3 (90 days) | |
| Container Insights | standard | enhanced (per task and per container) | For right-sizing and debugging prod. |
| ECS Exec | on | off | Dev is for debugging. In prod, shell access is something you turn on deliberately and temporarily. |
| Log retention | 7 days | 90 days | |
| KMS key / secret deletion window | 7 / 0 days | 30 / 30 days | Dev can be destroyed and rebuilt at any time. In prod, deleting something by mistake can be undone. |

---

## Decisions and trade-offs

These are the things I'd want to talk through in a review, including the ones I'm not fully happy with.

- **dev and prod are in the same AWS account.** I only have one account. In a real setup prod would be in its
  own account, and nothing in the code would need to change: `AWS_ACCOUNT_ID` decides the account, the state
  bucket is per account, and the provider refuses the wrong account.
- **HTTP only.** HTTPS needs a domain and an ACM certificate, which I don't have for this. The code is ready:
  set `certificate_arn` in `env.hcl` and the load balancer adds an HTTPS listener (TLS 1.2 and 1.3 only), and turns
  HTTP into a redirect to HTTPS.
- **The Redis auth token is in Terraform state.** Terraform generates it, so it's in the state file. The state
  bucket is private, encrypted and versioned, and the people who can read state are the same people who could
  read the secret anyway. The better fix is to let Secrets Manager generate and rotate the token without
  Terraform ever seeing it. That's on the list below.
- **CI only plans, it never applies.** For this task the plan was the deliverable, and I applied from my laptop
  while building. Each CI role is read-only, so a compromised workflow can't change anything. It also means
  plans run with `-lock=false`, because taking a lock needs write access. That's safe, since a plan never writes
  state.
- **Two units have no dev equivalent** (`alb-logs`, `vpc-endpoints`). I kept them as prod-only units rather than
  adding "off" switches to dev, because a unit that doesn't exist is clearer than one that's switched off.
- **The probe sidecar runs in prod too.** It's tiny, and it keeps checking the network, the security groups and
  the secret all the time. That's useful in prod. If the real app had its own Redis health check, I'd remove
  the probe.
- **Unit dependencies use mock outputs during plan.** That's what lets you plan an empty account, and lets CI
  plan prod before prod exists. The downside is that a plan of a fresh environment shows placeholder IDs for
  anything that comes from another unit.
- **A small known quirk.** Right after a fresh create, the load balancer unit shows a change in its outputs only
  (listener `tags` going from `null` to `{}`). This comes from the upstream module. It's harmless, and the next
  apply clears it.
- **nginx is a stand-in for the app.** The probe sidecar shows what the app would do with Redis, but there's no
  real application code using the connection.

---

## What I'd add with more time

Roughly in the order I'd do them:

1. **A domain and HTTPS.** A Route 53 record, an ACM certificate, and HTTP redirected to HTTPS. Right now the
   load balancer's address changes every time it's recreated.
2. **An apply pipeline.** Apply dev automatically when a change merges. Apply prod from the same commit after
   a manual approval in a GitHub environment, with the saved plan file as the thing that gets approved.
3. **Image promotion.** A private ECR repository, images tagged by git commit and scanned, and prod deploying
   the exact image that already ran in dev.
4. **Alarms and dashboards.** 5xx errors, unhealthy targets, Redis CPU and memory, failed deployments, and
   `redis-probe FAIL` turned into a metric with an alarm. All of it going to wherever on-call gets paged.
5. **Secret rotation.** Let Secrets Manager generate and rotate the Redis token, so it's never in Terraform state.
6. **WAF** in front of the prod load balancer, with the AWS managed rule sets and rate limiting.
7. **Separate accounts** for dev and prod under AWS Organizations, and a shared account for state and CI roles.
8. **Policy checks in CI**, for example "prod Redis must have Multi-AZ" or "no security group open to
   `0.0.0.0/0` except on the load balancer", plus a cost estimate on each pull request (Infracost).
9. **A real app.** A small service that actually uses Redis, with a `/health` endpoint that checks the
   connection, so the probe sidecar isn't needed any more.
10. **A Makefile and pre-commit hooks**, so `make plan ENV=dev` works and formatting is fixed before a commit
    rather than in CI.

---

## How I tested it

Everything below ran in my own AWS account (eu-central-1).

**dev**

- Built it one step at a time, checking each step: the load balancer returned 404 before any service existed,
  then nginx returned 200 through the load balancer once the service was deployed.
- Redis: the probe logged `OK` every 30 seconds. The Redis security group has exactly one inbound rule (6379
  from the service). TLS, encryption at rest and AUTH are all on.
- Autoscaling: sent about 13,000 requests over 6 minutes. The requests rule fired ("Setting desired count to
  2"), and the second task became healthy in the other AZ.
- Destroyed everything (67 resources, 9 minutes) and rebuilt it from scratch (67 resources, 10 minutes) with no
  manual steps. After that, a plan showed no changes.

**prod**

- Applied from zero: 8 units, 97 resources, 8 minutes.
- Three healthy on-demand tasks, one in each AZ. nginx returned 200 through the load balancer.
- Redis: three nodes in three AZs, failover and Multi-AZ on. The probe logged `OK`.
- Three NAT gateways, seven VPC endpoints, flow logs active, and load balancer access logs arriving in S3.
- Destroyed it again: 97 resources, 11 minutes. I then checked in AWS that nothing was left behind.

**CI**

- Both plan jobs log in through OIDC with their own read-only role, and the trust policy only accepts the
  matching GitHub environment. The repository uses GitHub's immutable OIDC subject, which identifies the owner
  and repository by numeric ID rather than by name. A deleted and re-created repository with the same name
  can't use these roles.
