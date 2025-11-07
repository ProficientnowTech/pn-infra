now, we need to plan a comprehensive storage pool architecture for different types of storage. mainly Object, RBD and CephFS (not used a lot). I want
you to present a comprehensive storage pool plan. What we're doing? Ans: we're building a platform for development teams who build different apps. and we
 need to divide the storage we have for all the use cases. such as, our own use: for example storing secrets, authentik databases, and databases and
object storage for our own use (infrastructure or platform) this storage again has different types of things stored. for example apart from active data
(database records) we also store telemetry data right? and then in telemetry and observability data, we store older data as well. logs, traces, metrics
and other stuff. then we also have other types of data. so we need a smart way to store and manage all types of different data. large pools should be
allowed (with the tiers and everything) to application clusters (environment specific). the plan documents if they include designs should only contain
designs in mermaid diagrams. have reasoning for every decision. follow openspec system to create a detailed spec and change proposal for the system. the
databases deployed are going to be StackGres (clusters) now you should know that the tenant to the saas application is not our tenant. our tenant from
our perspective is the team who manages the SaaS. their multitenancy is very different from our multitenancy. we can create StackGres clusters per layer
(infra/platform/application-infra/application) or whatever layers you want to divide into. and each cluster will have different databases per tenant.
makes sense? but for application-infra, we might need separate clusters for separate applications deployed. that should be left for them to decide. it
could be a schema based sharded multi-tenant architecture. this is important and we will have back and forth to change this design.