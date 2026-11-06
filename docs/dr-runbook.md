# Disaster recovery runbook

**Scope:** the web service in `us-east-1` (primary) and its warm standby in `us-west-2`, behind one Route 53 name.

**Status:** written from the design, **not executed**, because the stack is plan-only. Commands are the ones I would run, and each should be verified in a test account first. Items marked **VERIFY** depend on behavior I could not test offline.

## 0. Recovery targets

| | Target | Basis |
|---|---|---|
| RPO | 15 minutes | S3 Replication Time Control, watched by the replication-latency alarm |
| RTO | 10 minutes | Up to 90 s to detect, up to 60 s for DNS caches, the standby already runs, then 2 to 5 minutes of autoscaling |

These are design targets. Section 6 records the **measured** values, which replace them after the first game day.

## 1. First deployment, in this order

The order matters. Starting the service before the secret has a value fails every task.

1. **Apply** the Terraform. Set real values for the account ID, hosted zone, domain name, certificate ARNs (one per region) and the two log bucket names.
2. **Confirm the email subscriptions.** There are three topics: the primary alerts, the DR alerts and the backup events. Each sends a confirmation email that must be clicked, or no alarm will reach anyone.
3. **Set the secret value** once, out of band:
   `aws secretsmanager put-secret-value --secret-id webapp-prod/app-secret --secret-string '<value>' --region us-east-1`
   Then confirm the replica exists: `aws secretsmanager describe-secret --secret-id webapp-prod/app-secret --region us-west-2`.
4. **Push the image.** Tags are immutable, so use a new version each time:
   - `aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin <account>.dkr.ecr.us-east-1.amazonaws.com`
   - `docker build -t webapp-prod/app:1.0.0 ./app`
   - `docker tag webapp-prod/app:1.0.0 <account>.dkr.ecr.us-east-1.amazonaws.com/webapp-prod/app:1.0.0`
   - `docker push <account>.dkr.ecr.us-east-1.amazonaws.com/webapp-prod/app:1.0.0`
5. **Check replication:** `aws ecr describe-images --repository-name webapp-prod/app --region us-west-2` must list `1.0.0`.
6. **Check both services are healthy:** the dashboards in both regions show running tasks equal to desired, and zero unhealthy hosts.
7. **Check the name:** `curl https://app.example.com/` returns `"region": "us-east-1"`.

## 2. Failover

### Automatic

1. The health check fails 3 times in a row (about 90 seconds).
2. Route 53 starts answering with the DR load balancer. Clients follow as their DNS cache expires (up to 60 seconds).
3. The failover alarm (`webapp-prod-primary-unhealthy`) notifies the team.
4. The request-count policy adds tasks in the DR region as traffic arrives.

### Manual (planned failover or a drill)

Force the health check to report the primary as unhealthy without touching the primary:

`aws route53 update-health-check --health-check-id <id> --inverted`

Undo it with `--no-inverted`. To add capacity ahead of the traffic:

`aws ecs update-service --cluster webapp-prod-dr-cluster --service webapp-prod-dr-app --desired-count 3 --region us-west-2`

### Verify the DR region is serving

- `curl https://app.example.com/` returns `"region": "us-west-2"`.
- The DR dashboard shows requests arriving and zero 5xx errors.
- The DR running-tasks alarm is not firing.

## 3. Failback

Data written during the failover exists only in the replica bucket. Writes are **not** copied back automatically.

1. Confirm the primary region is healthy again: the primary load balancer's targets are healthy and the primary running-tasks alarm is clear.
2. **Copy the data back** before sending traffic: `aws s3 sync s3://<replica-bucket>/app/ s3://<primary-bucket>/app/` (or S3 Batch Operations for a large bucket). Compare object counts afterwards.
3. Undo the inverted health check (`--no-inverted`), or let it recover on its own.
4. Watch traffic return to `"region": "us-east-1"`.
5. Scale the DR service back to its standby size (1 task).
6. Write up what happened, and update the targets if they were missed.

## 4. Restoring from backup

Replication copies mistakes, so a bad write or delete is undone from backup, not by failing over.

1. Find the moment to restore to (CloudTrail, application logs, or the user's report).
2. In AWS Backup, choose the primary vault and start a **point-in-time restore** of the data bucket to a **new** bucket. Never restore over the live one.
3. Compare the restored objects with the current ones, and copy back only what is needed.
4. If the primary region is unavailable, restore from the DR vault's copy into the DR region.
5. **VERIFY** the restore permissions: the backup role can use the bucket keys in both regions.

## 5. When an alarm fires

| Alarm | First checks |
|---|---|
| Target 5xx | Container logs in `/ecs/webapp-prod-<region>`, then the last deployment (the circuit breaker may already have rolled it back) |
| Unhealthy hosts | The health endpoint, task events in the ECS console, whether a deployment is in progress |
| p95 latency | CPU and memory alarms, request count, the database or any downstream dependency |
| CPU or memory high | Whether autoscaling is at its maximum of 6, then raise the maximum or the task size |
| Running tasks low | Task stop reasons: out of memory, a failing health check, or the secret missing |
| Replication latency | Replication metrics, the replication role, and key permissions in both regions |
| Primary unhealthy (Route 53) | Treat it as a live failover: section 2 |
| Backup job failed | The job's status message, the backup role, and key permissions |

## 6. Game day (every quarter)

1. Announce the window and who is on call.
2. Record the start time, then invert the health check (section 2).
3. Note when `curl https://app.example.com/` first answers from `us-west-2` (**time to traffic**).
4. Note when the DR service reaches full capacity (**time to full capacity**).
5. Write an object to the primary bucket just before the drill, and note how long it takes to appear in the replica (**measured replication delay**).
6. Fail back (section 3).
7. Record the measured values here, and compare them with the targets.

| Date | Time to traffic | Time to full capacity | Replication delay | Notes |
|---|---|---|---|---|
| not yet run | | | | |
