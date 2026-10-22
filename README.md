# mirrord ECS quickstart

Run a service on your laptop as if it were running in Amazon ECS. No image build, no push, no redeploy.

This repo deploys a small orders API to ECS on Fargate, next to a private Postgres database on RDS. Then you run the same service locally with [mirrord](https://metalbear.com/mirrord/), and see two things:

- **Incoming traffic:** requests to the public load balancer that carry your session header reach the process on your laptop. All other requests still go to the ECS task.
- **Outgoing traffic:** your local process connects to the RDS database, which has no public endpoint. The connection leaves from the ECS task, inside the VPC. mirrord also gives the local process the task's environment variables, so it gets the database credentials from the task.

```
                       ┌──────────────── VPC ────────────────────────────┐
 curl ──► ALB ────────►│ ECS task (Fargate)                              │
          │            │  orders app + mirrord remote bootstrap ──► RDS  │
          │            └──────────────┬──────────────────────────────────┘
          │                           │ outbound HTTPS
          │                 MetalBear sessions-manager
          │                           │
          │   with header             ▼
          └─ baggage: mirrord-session=quickstart ──► your laptop: uvicorn under mirrord exec
```

> mirrord for ECS is experimental. You need a MetalBear API key for serverless workloads and the dedicated mirrord CLI build. [Contact us](https://metalbear.com/mirrord/) to get both.

## What you need

- An AWS account and the AWS CLI, signed in.
- Terraform 1.6 or later.
- Python 3.12 (the app also runs in other Python 3 versions that FastAPI supports).
- The mirrord CLI build for serverless workloads, on your `PATH`.
- A MetalBear API key for serverless workloads. It begins with `metalbear_key_`.

> **Cost:** this creates billable resources: a NAT gateway, an Application Load Balancer, a `db.t4g.micro` RDS instance and one Fargate task. Run `terraform destroy` when you finish.

## 1. Deploy the service to ECS

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # then put your API key in it
terraform init
terraform apply
```

It takes about 10 minutes, mostly for RDS. When it finishes, keep the URL:

```bash
export URL=$(terraform output -raw url)
curl $URL/orders
```

The response comes from the ECS task, with `"version": "v1"`.

## 2. Run the service locally with mirrord

Sign in once, and install the app's dependencies:

```bash
mirrord login

cd ../app
python3 -m venv .venv && . .venv/bin/activate
pip install -r requirements.txt
```

Open `app/main.py` and change the code, for example:

```python
GREETING = "Hello from my laptop"
VERSION = "v2"
```

Run it with mirrord, from the repo root:

```bash
cd ..
mirrord exec -f mirrord.json -- uvicorn main:app --app-dir app --port 8080
```

## 3. See it work

Send a request with your session header:

```bash
curl -H "baggage: mirrord-session=quickstart" $URL/
curl -H "baggage: mirrord-session=quickstart" $URL/orders
```

Both responses show `"version": "v2"`: your local code served them. The `/orders` response also lists the rows from the private RDS database, which your laptop has no route to.

Now send the same request without the header:

```bash
curl $URL/orders
```

It shows `"version": "v1"`. The ECS task still serves everyone else, so other developers and other traffic are not affected.

Add an order from your local code, and see the deployed service read it from the same database:

```bash
curl -X POST -H "baggage: mirrord-session=quickstart" \
  -H "content-type: application/json" -d '{"item": "bagel"}' $URL/orders
curl $URL/orders
```

Change the code again, restart `mirrord exec`, and send the request again. There is no image build and no deploy between changes.

## How it works

`mirrord.json` targets the ECS service by the names the task registers under:

| Setting | Value | Set on the task by |
| --- | --- | --- |
| `target.path` | `serverless/orders` | `MIRRORD_REMOTE_SERVICE` |
| `target.namespace` | `quickstart` | `MIRRORD_REMOTE_ENVIRONMENT` |

The task definition in [`terraform/ecs.tf`](terraform/ecs.tf) has the changes that make the service targetable:

1. A setup container copies the mirrord remote bootstrap into a shared volume before the app starts.
2. The app container loads the bootstrap with `LD_PRELOAD`. The app image does not change.
3. ECS injects the API key from Secrets Manager as `MIRRORD_SESSIONS_MANAGER_API_KEY`.

The task and your laptop both make only outbound HTTPS connections to MetalBear's sessions-manager, which pairs them. Nothing in your VPC accepts inbound connections from outside.

`mirrord.json` steals only HTTP requests whose `baggage` header carries the session key `quickstart`. To use a different key, change `key` in `mirrord.json` or set `MIRRORD_KEY`, and send that key in the header.

To set this up on your own services, see the [mirrord docs for Amazon ECS](https://metalbear.com/mirrord/docs/using-mirrord/serverless/ecs).

## Operator-hosted mode

If you already run the mirrord Operator on EKS, the ECS task can connect through it instead of MetalBear Cloud. Then you need no API key, and access uses Kubernetes RBAC.

1. [Enable sessions-manager](https://metalbear.com/mirrord/docs/using-mirrord/serverless/operator-hosted) on the Operator.
2. Bind the `mirrord-ecs-workloads` group to the `mirrord-operator-sessions-manager-agent` ClusterRole, as the [ECS operator guide](https://metalbear.com/mirrord/docs/using-mirrord/serverless/ecs-operator-hosted) shows.
3. In `terraform.tfvars`, set `eks_cluster_name` instead of `mirrord_api_key`. Terraform creates a task role and maps it into that group with an EKS access entry.
4. In `mirrord.json`, add `"operator": true`, and use a kubeconfig context for that cluster.

This repo reaches the EKS API server through its public endpoint and the NAT gateway. If your API server is private only, follow the networking steps in the ECS operator guide.

## Notes

- **ECS on EC2:** the same task definition changes work on EC2 launch types. This repo uses Fargate because it needs no instances.
- **One task:** a mirrord session is served by one replica, so the service runs one task.
- **Base image:** the bootstrap needs a glibc 2.30 or later image. Alpine (musl) images are not supported. The app uses `python:3.12-slim-bookworm`.
- **Your own image:** the default image is built from `app/` by the workflow in `.github/workflows/image.yml`. To use your own, set `app_image` in `terraform.tfvars`.

## Clean up

```bash
cd terraform
terraform destroy
```
