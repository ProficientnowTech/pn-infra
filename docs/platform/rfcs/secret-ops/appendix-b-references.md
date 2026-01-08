```
RFC-SECOPS-0001                                           Appendix B
Category: Standards Track                              References
```

# Appendix B: References

[← Previous: Glossary](./appendix-a-glossary.md) | [Index](./00-index.md#table-of-contents)

---

This appendix provides normative and informative references for the concepts,
standards, and technologies discussed in this RFC.

---

## B.1 Normative References

The following references are essential to understanding the terminology and
requirements specified in this RFC.

---

### IETF Standards

**[RFC2119]** Bradner, S., "Key words for use in RFCs to Indicate Requirement
Levels", BCP 14, RFC 2119, DOI 10.17487/RFC2119, March 1997.
<https://datatracker.ietf.org/doc/html/rfc2119>

**[RFC8174]** Leiba, B., "Ambiguity of Uppercase vs Lowercase in RFC 2119 Key
Words", BCP 14, RFC 8174, DOI 10.17487/RFC8174, May 2017.
<https://datatracker.ietf.org/doc/html/rfc8174>

---

### NIST Publications

**[SP800-57pt1]** Barker, E., "Recommendation for Key Management: Part 1 –
General", NIST Special Publication 800-57 Part 1 Revision 5, May 2020.
<https://csrc.nist.gov/pubs/sp/800/57/pt1/r5/final>

**[SP800-57pt2]** Barker, E. and Barker, W., "Recommendation for Key
Management: Part 2 – Best Practices for Key Management Organizations",
NIST Special Publication 800-57 Part 2 Revision 1, March 2019.
<https://csrc.nist.gov/pubs/sp/800/57/pt2/r1/final>

**[SP800-152]** Barker, E. and Smid, M., "A Profile for U.S. Federal
Cryptographic Key Management Systems", NIST Special Publication 800-152,
October 2015.
<https://nvlpubs.nist.gov/nistpubs/specialpublications/nist.sp.800-152.pdf>

---

## B.2 Technology Documentation

The following references provide official documentation for the technologies
referenced in this architecture.

---

### HashiCorp Vault

**[VAULT-DOCS]** HashiCorp, "Vault Documentation".
<https://developer.hashicorp.com/vault>

**[VAULT-SECRETS]** HashiCorp, "Secrets Management Tutorials".
<https://developer.hashicorp.com/vault/tutorials/secrets-management>

**[VAULT-K8S]** Plural, "HashiCorp Vault Kubernetes: The Definitive Guide".
<https://www.plural.sh/blog/hashicorp-vault-kubernetes-guide/>

---

### External Secrets Operator

**[ESO-DOCS]** External Secrets, "External Secrets Operator Documentation".
<https://external-secrets.io/>

**[ESO-PUSHSECRET]** External Secrets, "PushSecret Documentation". *(v1.1)*
<https://external-secrets.io/latest/api/pushsecret/>

**[ESO-ARGOCD]** Codefresh, "Securing GitOps with External Secrets Operator &
AWS Secrets Manager".
<https://codefresh.io/blog/aws-external-secret-operator-argocd/>

**[ESO-OPENSHIFT]** Red Hat, "Introducing the External Secrets Operator for
OpenShift", November 2025.
<https://developers.redhat.com/articles/2025/11/11/introducing-external-secrets-operator-openshift>

---

### Bitnami Sealed Secrets

**[SEALED-SECRETS]** Bitnami Labs, "Sealed Secrets: A Kubernetes controller
and tool for one-way encrypted Secrets".
<https://github.com/bitnami-labs/sealed-secrets>

**[SEALED-SECRETS-CHART]** Bitnami, "Sealed Secrets Helm Chart".
<https://github.com/bitnami/charts/blob/main/bitnami/sealed-secrets/README.md>

---

### Argo CD

**[ARGOCD-SECRETS]** Argo Project, "Secret Management in Argo CD".
<https://argo-cd.readthedocs.io/en/stable/operator-manual/secret-management/>

---

## B.3 Informative References

The following references provide background, best practices, and alternative
perspectives on secrets management.

---

### Industry Best Practices

**[GITOPS-SECRETS-REDHAT]** Red Hat, "A Guide to Secrets Management with
GitOps and Kubernetes", 2025.
<https://www.redhat.com/en/blog/a-guide-to-secrets-management-with-gitops-and-kubernetes>

**[GITOPS-SECRETS-MS]** Microsoft, "Secrets Management with GitOps",
Engineering Fundamentals Playbook.
<https://microsoft.github.io/code-with-engineering-playbook/CI-CD/gitops/secret-management/>

**[GITOPS-SECRETS-HARNESS]** Harness, "GitOps For Secrets Management".
<https://www.harness.io/blog/gitops-secrets>

**[VAULT-HARDENING]** SJ Ramblings, "Secure Your Secrets: Best Practices for
Hardening HashiCorp Vault in Production".
<https://sjramblings.io/secure-your-secrets-best-practices-for-hardening-hashicorp-vault-in-production/>

---

### Security Guidance

**[OWASP-KEYS]** OWASP, "Key Management Cheat Sheet".
<https://cheatsheetseries.owasp.org/cheatsheets/Key_Management_Cheat_Sheet.html>

**[CMS-KEY-MGMT]** CMS, "CMS Key Management Handbook".
<https://security.cms.gov/learn/cms-key-management-handbook>

**[NIST-KEY-MGMT]** NIST, "Key Management Guidelines".
<https://csrc.nist.gov/projects/key-management/key-management-guidelines>

---

### Comparison and Analysis

**[SECRETS-2026]** Java Code Geeks, "Secrets Management in 2026: Vault, AWS
Secrets Manager, and Beyond - A Developer's Guide", December 2025.
<https://www.javacodegeeks.com/2025/12/secrets-management-in-2026-vault-aws-secrets-manager-and-beyond-a-developers-guide.html>

---

## B.4 Related Standards

The following standards are relevant to understanding the broader context of
secrets and key management.

---

### Kubernetes Enhancement Proposals

**[KEP-2579]** Secret encryption at rest enhancements.

**[KEP-1751]** External secret storage integration.

---

### Zero Trust Architecture

**[SP800-207]** NIST, "Zero Trust Architecture", NIST Special Publication
800-207, August 2020.
<https://csrc.nist.gov/publications/detail/sp/800-207/final>

---

## B.5 Further Reading

The following resources provide deeper context on the architectural patterns
and operational philosophies referenced in this RFC.

---

### GitOps Patterns

- Weaveworks, "GitOps: What You Need to Know"
- CNCF, "OpenGitOps Principles"
- Argo Project, "Argo CD Best Practices"

---

### Platform Engineering

- Team Topologies by Matthew Skelton and Manuel Pais
- "Platform as a Product" patterns
- CNCF Platform Working Group materials

---

### Cryptographic Key Management

- NIST Key Management Guidelines portal
- Cloud Security Alliance guidance on key management
- OWASP Cryptographic Storage Cheat Sheet

---

## B.6 Acknowledgments

This RFC draws on concepts and patterns from the broader cloud-native
community, including:

- The HashiCorp community and Vault project
- The External Secrets Operator maintainers
- The Argo Project and GitOps community
- NIST cryptographic key management working groups
- OWASP security guidance contributors

---

## Document Navigation

| Previous | Index | Next |
|----------|-------|------|
| [← Appendix A: Glossary](./appendix-a-glossary.md) | [Table of Contents](./00-index.md#table-of-contents) | — |

---

## Author's Address

**Shaik Noorullah Shareef**
Platform Engineering

---

*End of Appendix B*

---

*End of RFC-SECOPS-0001*
