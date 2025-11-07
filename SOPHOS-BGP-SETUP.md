# Sophos XGS136 BGP Configuration for MetalLB

## Overview
This guide configures BGP peering between Sophos XGS136 firewall and MetalLB to enable direct routing of public IPs (103.110.174.18-25) to Kubernetes LoadBalancer services.

## Network Architecture

```
Internet
    ↓
Sophos XGS136 (172.17.0.1) - AS 65000
    ↓ BGP Peering
K8s Cluster (MetalLB) - AS 64512
    ↓
LoadBalancer Services (103.110.174.18-25)
```

## Prerequisites
- Sophos XGS136 with BGP support
- Public IP range: 103.110.174.18-25
- Network connectivity between Sophos (172.17.0.1) and K8s nodes
- Admin access to Sophos firewall

## Step 1: Configure BGP on Sophos XGS136

### Access Sophos Web Interface
1. Navigate to https://172.17.0.1:4444
2. Login with admin credentials

### Enable BGP Feature
1. Go to **Routing → Dynamic Routing → BGP**
2. Enable BGP if not already enabled
3. Click **Add** or **Configure**

### Configure BGP Settings

#### Basic BGP Configuration:
- **Router ID**: 172.17.0.1 (Sophos firewall IP)
- **AS Number**: 65000
- **Networks to Advertise**: None (we're only receiving routes from MetalLB)

#### Add BGP Neighbor (MetalLB):

You need to add each K8s master node as a BGP neighbor. Get the K8s node IPs first:

```bash
kubectl get nodes -o wide
```

For each master node, add a BGP neighbor with these settings:

- **Neighbor IP**: [K8s Node IP] (e.g., IP of k8s-master-01, k8s-master-02, k8s-master-03)
- **Remote AS**: 64512
- **Description**: MetalLB on k8s-master-XX
- **Next-hop-self**: Disabled
- **Default Originate**: Disabled
- **Activate**: Enabled
- **Authentication**: None (or set password and add to metallb-bgppeer.yaml)

**Important**: Add all K8s master nodes as BGP neighbors for redundancy.

#### Route Map (Optional but Recommended):
Create a route map to accept only specific prefixes from MetalLB:

1. Go to **Routing → Route Maps**
2. Create new route map: `accept-metallb-routes`
3. Add permit rule for prefix: 103.110.174.0/24
4. Apply this route map to BGP neighbors (in neighbor configuration)

### Configure Firewall Rules

1. Go to **Rules and Policies → Firewall Rules**
2. Add rule to allow BGP traffic:
   - **Source**: K8s node IPs
   - **Destination**: Sophos firewall (172.17.0.1)
   - **Service**: BGP (TCP/179)
   - **Action**: Accept

3. Add rule to allow traffic to public IPs:
   - **Source**: Any (or specific allowed sources)
   - **Destination**: 103.110.174.18-103.110.174.25
   - **Service**: HTTPS, HTTP (or as needed)
   - **Action**: Accept

### Configure NAT (Important!)

**Disable Source NAT** for traffic to the public IP range:

1. Go to **Rules and Policies → NAT Rules**
2. Find your existing SNAT/Masquerade rule for internet traffic
3. Add an **exception** or create a rule BEFORE the masquerade rule:
   - **Source**: Any
   - **Destination**: 103.110.174.18-103.110.174.25
   - **Action**: None (or Skip NAT)
   - **Position**: Before other SNAT rules

This ensures traffic to MetalLB IPs is not NAT'd.

## Step 2: Deploy MetalLB BGP Configuration

The MetalLB configuration has been updated in:
- `/v0.2.0/platform/bootstrap/metallb-addresspool/`

To apply the changes:

```bash
# Delete old L2Advertisement
kubectl delete l2advertisement default-l2advertisement -n metallb-system

# Delete old IPAddressPool
kubectl delete ipaddresspool default-pool -n metallb-system

# Apply new BGP configuration
kubectl apply -k v0.2.0/platform/bootstrap/metallb-addresspool/
```

This creates:
- **IPAddressPool** `public-pool` with IPs 103.110.174.18-25
- **BGPAdvertisement** announcing the pool via BGP
- **BGPPeer** connecting to Sophos at 172.17.0.1

## Step 3: Verify BGP Peering

### On Sophos:
1. Go to **Routing → Dynamic Routing → BGP → Neighbors**
2. Check neighbor status - should show **Established**
3. Go to **Routing → Route Table**
4. Verify routes from MetalLB appear (103.110.174.x/32 routes)

### On Kubernetes:

```bash
# Check BGP peer status
kubectl get bgppeers -n metallb-system

# Check MetalLB speaker logs
kubectl logs -n metallb-system -l component=speaker | grep BGP

# You should see messages like:
# "BGP session with 172.17.0.1:179 established"
# "Announced route for 103.110.174.18/32"
```

### Test BGP Routes:

```bash
# Check if MetalLB assigned new public IPs to services
kubectl get svc -A -o wide | grep LoadBalancer

# The ingress-nginx LoadBalancer should now have a public IP (103.110.174.x)
# instead of internal IP (192.168.101.x)
```

## Step 4: Update Existing Services

Since we changed the IP pool, existing LoadBalancer services will keep their old IPs. To get new public IPs:

### Option 1: Delete and recreate the service
```bash
kubectl delete svc ingress-nginx-controller -n ingress-nginx
# ArgoCD will recreate it with new public IP
```

### Option 2: Change service type temporarily
```bash
kubectl patch svc ingress-nginx-controller -n ingress-nginx -p '{"spec":{"type":"ClusterIP"}}'
sleep 5
kubectl patch svc ingress-nginx-controller -n ingress-nginx -p '{"spec":{"type":"LoadBalancer"}}'
```

## Step 5: Remove External-DNS Annotation Override

Since we now have direct public IPs, remove the manual annotation:

```bash
kubectl annotate ingress argocd-server-ingress -n argocd external-dns.alpha.kubernetes.io/target-
```

External-DNS will now automatically use the public LoadBalancer IP from the service status.

## Troubleshooting

### BGP Session Not Establishing

**Check connectivity:**
```bash
# From K8s node
ping 172.17.0.1
telnet 172.17.0.1 179
```

**Check MetalLB logs:**
```bash
kubectl logs -n metallb-system -l component=speaker --tail=100 | grep -i bgp
```

**Common issues:**
- Firewall blocking TCP/179
- Incorrect AS numbers
- Wrong peer IP address
- Sophos BGP not enabled

### Routes Not Appearing on Sophos

**Check MetalLB is advertising:**
```bash
kubectl logs -n metallb-system -l component=speaker | grep "Announced"
```

**Check Sophos route map:**
- Ensure route map allows 103.110.174.0/24
- Check neighbor is activated

### Services Not Getting Public IPs

**Check IPAddressPool:**
```bash
kubectl get ipaddresspool -n metallb-system public-pool -o yaml
```

**Force service recreation:**
```bash
kubectl delete svc <service-name> -n <namespace>
# Let ArgoCD recreate it
```

## Security Considerations

1. **BGP Authentication**: Consider adding MD5 password authentication
   - Add to Sophos neighbor config
   - Add to `metallb-bgppeer.yaml` spec.password

2. **Route Filtering**: Use route maps on Sophos to only accept expected prefixes

3. **Firewall Rules**: Restrict source IPs that can reach public IPs

4. **Monitoring**: Set up alerts for BGP session state changes

## Rollback Plan

If issues occur, rollback to L2 mode:

```bash
# Delete BGP resources
kubectl delete bgppeer sophos-firewall -n metallb-system
kubectl delete bgpadvertisement public-bgp-advertisement -n metallb-system
kubectl delete ipaddresspool public-pool -n metallb-system

# Reapply L2 configuration
kubectl apply -f v0.2.0/platform/bootstrap/metallb-addresspool/metallb-ipaddresspool-l2-backup.yaml
kubectl apply -f v0.2.0/platform/bootstrap/metallb-addresspool/metallb-l2advertisement.yaml
```

## Configuration Summary

| Component | Setting | Value |
|-----------|---------|-------|
| Sophos BGP AS | AS Number | 65000 |
| Sophos Router ID | IP Address | 172.17.0.1 |
| MetalLB BGP AS | AS Number | 64512 |
| BGP Peer Address | Sophos IP | 172.17.0.1 |
| Public IP Pool | Range | 103.110.174.18-25 |
| Protocol | BGP Version | 4 |

## Next Steps

After BGP is working:
1. Monitor BGP session stability for 24 hours
2. Test failover by stopping MetalLB speaker on one node
3. Document any custom route policies
4. Set up monitoring/alerting for BGP state
5. Update runbooks for BGP troubleshooting
