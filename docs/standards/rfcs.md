# RFC Authoring Standards

## Status of This Document

This document defines the authoritative standards for authoring Request for
Comments (RFC) documents within this organization. All RFC authors MUST adhere
to these standards.

---

## 1. Introduction

### 1.1 Purpose

This document establishes a standardized framework for creating RFC documents.
RFCs serve as the primary mechanism for proposing, documenting, and preserving
architectural decisions for platform systems.

### 1.2 Scope

These standards apply to all RFC documents created within the `docs/platform/rfcs/`
directory hierarchy.

### 1.3 Conformance Language

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD",
"SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this
document are to be interpreted as described in BCP 14 [RFC2119] [RFC8174] when,
and only when, they appear in all capitals.

---

## 2. RFC Identity and Classification

### 2.1 RFC Identifier Format

Each RFC MUST have a unique identifier following this format:

```
RFC-<DOMAIN>-<NUMBER>
```

Where:
- `<DOMAIN>` is a short uppercase identifier for the problem domain (e.g., SECOPS, DEPLOY, NETWORK)
- `<NUMBER>` is a zero-padded four-digit sequential number (e.g., 0001, 0002)

**Examples:**
- `RFC-SECOPS-0001` — Secret operations
- `RFC-DEPLOY-0001` — Deployment orchestration
- `RFC-NETOPS-0001` — Network operations

### 2.2 RFC Status Values

Each RFC MUST declare one of the following status values:

| Status | Meaning |
|--------|---------|
| Draft | Under active development, subject to change |
| Review | Complete draft awaiting review |
| Accepted | Approved for implementation |
| Implemented | Architecture has been implemented |
| Superseded | Replaced by a newer RFC |
| Withdrawn | No longer applicable |

### 2.3 RFC Categories

Each RFC MUST declare a category:

| Category | Use |
|----------|-----|
| Standards Track | Architectural specifications intended for implementation |
| Informational | Documentation, guidelines, or background information |
| Experimental | Proposals for evaluation before standardization |

---

## 3. Document Structure

### 3.1 Required File Structure

Each RFC MUST be organized as a directory containing multiple markdown files:

```
docs/platform/rfcs/<domain>/
├── 00-index.md              # REQUIRED: Master index
├── 01-introduction.md       # REQUIRED: Problem space
├── 02-requirements.md       # REQUIRED: Constraints and invariants
├── 03-architecture.md       # REQUIRED: High-level design
├── 04-components.md         # REQUIRED: Building blocks
├── 05-*.md                  # Domain-specific sections
├── ...
├── NN-rationale.md          # REQUIRED: Rejected alternatives
├── NN-evolution.md          # RECOMMENDED: Future considerations
├── appendix-a-glossary.md   # REQUIRED: Terms and indexes
└── appendix-b-references.md # REQUIRED: Citations
```

### 3.2 File Naming Conventions

- Files MUST use lowercase with hyphens as separators
- Files MUST be prefixed with two-digit section numbers for ordering
- Section numbers MUST be sequential starting from 00
- Appendices MUST use the format `appendix-<letter>-<name>.md`

### 3.3 Required Sections

Every RFC MUST contain:

1. **Index** (00-index.md)
   - RFC metadata table
   - Abstract
   - Table of contents
   - Reading paths for different audiences

2. **Introduction** (01-introduction.md)
   - Background and context specific to THIS RFC's problem
   - Current state description
   - Operational shortcomings being addressed
   - Motivation for the architecture

3. **Requirements** (02-requirements.md)
   - Problem restatement
   - Design goals
   - Non-goals (explicit exclusions)
   - Architectural invariants
   - Success criteria

4. **Architecture** (03-architecture.md)
   - High-level system overview
   - Phase or state model (if applicable)
   - Authority domains
   - Trust boundaries

5. **Components** (04-components.md)
   - System building blocks
   - Component responsibilities
   - Interfaces and contracts
   - Failure modes

6. **Rationale** (required, number varies)
   - Rejected alternatives
   - Trade-off analysis
   - Decision justification

7. **Glossary** (appendix-a-glossary.md)
   - Term definitions
   - ADR index
   - Diagram index

8. **References** (appendix-b-references.md)
   - Normative references
   - Informative references
   - Internal references

---

## 4. Content Requirements

### 4.1 Originality

Each RFC MUST contain original content specific to its problem domain.

Authors MUST NOT:
- Copy prose from other RFCs
- Reuse context-specific narratives
- Duplicate problem statements from unrelated RFCs

Authors MAY:
- Follow the same structural patterns
- Use consistent formatting conventions
- Reference other RFCs for related concepts

### 4.2 What RFCs MUST Include

RFCs MUST:

1. **Establish context and motivation**
   - Define the problem space unique to this RFC
   - Explain why this architecture is necessary
   - Describe the specific operational pain points being addressed

2. **Define guarantees and contracts**
   - Specify what the system guarantees
   - Define interfaces and their contracts
   - Document behavioral expectations

3. **Specify invariants**
   - List rules that MUST always hold true
   - Use RFC 2119 keywords for requirement levels
   - Explain consequences of invariant violation

4. **Document design at multiple levels**
   - High level: Overall system behavior and properties
   - Medium level: Component interactions and relationships
   - Low level: Internal component details and mechanics

5. **Provide rationale for decisions**
   - Document alternatives considered
   - Explain why alternatives were rejected
   - Reference which invariants each alternative violated

6. **Include glossary and references**
   - Define all domain-specific terms
   - Cite normative and informative sources
   - Index architectural decisions

### 4.3 What RFCs MUST NOT Include

RFCs MUST NOT:

1. **Include implementation code**
   - No code examples or snippets
   - No configuration samples
   - No shell commands or scripts
   - Implementation details belong in separate documents

2. **Specify timelines or durations**
   - No time estimates for tasks
   - No scheduling predictions
   - No phase duration specifications
   - Focus on sequence and dependencies, not timing

3. **Define implementation tasks**
   - No step-by-step implementation guides
   - No task lists or checklists
   - No "how to implement" instructions
   - Implementation planning belongs in separate documents

4. **Make implicit assumptions**
   - Every assumption MUST be explicitly stated
   - No reliance on tribal knowledge
   - No "obvious" prerequisites left unstated
   - All dependencies MUST be documented

5. **Include emotional or promotional language**
   - No superlatives ("best", "fastest", "revolutionary")
   - No marketing language
   - Technical precision over enthusiasm
   - Objective assessment over advocacy

### 4.4 Behavioral Specification

RFCs describe **what** systems do and **why**, not **how** to build them.

| RFC Scope | Implementation Scope |
|-----------|---------------------|
| System behavior | Code structure |
| Guarantees provided | Algorithms used |
| Interfaces exposed | Data structures |
| Failure semantics | Error handling code |
| State transitions | State machine implementation |

---

## 5. Formatting Standards

### 5.1 Document Header

Each file MUST begin with a header block:

```markdown
```
RFC-<ID>                                              Section N
Category: <Category>                              <Section Title>
```

# N. Section Title

[← Previous: Title](./file.md) | [Index](./00-index.md#table-of-contents) | [Next: Title →](./file.md)

---
```

### 5.2 Section Numbering

- Top-level sections use single integers (1, 2, 3)
- Subsections use decimal notation (1.1, 1.2, 2.1)
- Maximum depth SHOULD be three levels (1.1.1)

### 5.3 Navigation Footer

Each file MUST end with a navigation footer:

```markdown
---

## Document Navigation

| Previous | Index | Next |
|----------|-------|------|
| [← N-1. Title](./file.md) | [Table of Contents](./00-index.md#table-of-contents) | [N+1. Title →](./file.md) |

---

*End of Section N*
```

### 5.4 Tables

Tables SHOULD be used for:
- Requirement matrices
- Component comparisons
- Status mappings
- Reference indexes

Tables MUST have headers and consistent column alignment.

### 5.5 Diagrams

Diagrams MUST use Mermaid syntax for:
- Architecture overviews (flowchart)
- Sequence flows (sequenceDiagram)
- State machines (stateDiagram-v2)

All diagrams MUST be indexed in Appendix A.

### 5.6 Code Blocks

Code blocks are permitted ONLY for:
- Mermaid diagrams
- File paths and identifiers
- Configuration keys (without values)
- Format specifications

Code blocks MUST NOT contain:
- Implementation code
- Working configuration
- Shell commands
- Scripts

---

## 6. Language and Style

### 6.1 RFC 2119 Keywords

Use RFC 2119 keywords for requirement specification:

| Keyword | Meaning |
|---------|---------|
| MUST | Absolute requirement |
| MUST NOT | Absolute prohibition |
| REQUIRED | Equivalent to MUST |
| SHALL | Equivalent to MUST |
| SHALL NOT | Equivalent to MUST NOT |
| SHOULD | Recommendation |
| SHOULD NOT | Not recommended |
| RECOMMENDED | Equivalent to SHOULD |
| MAY | Optional |
| OPTIONAL | Equivalent to MAY |

Keywords MUST appear in ALL CAPITALS when used normatively.

### 6.2 Voice and Tense

- Use present tense for describing system behavior
- Use active voice where possible
- Avoid first person ("I", "we")
- Refer to the system or specific components as subjects

**Correct:** "The orchestrator executes nodes in dependency order."
**Incorrect:** "We will execute nodes in dependency order."

### 6.3 Technical Precision

- Define terms before using them
- Use consistent terminology throughout
- Avoid synonyms for technical terms
- Reference the glossary for definitions

### 6.4 Objectivity

- Present facts without advocacy
- Document trade-offs neutrally
- Acknowledge limitations explicitly
- Avoid defensive or promotional language

---

## 7. Invariants and Requirements

### 7.1 Invariant Specification

Invariants MUST be:
- Numbered sequentially (INV-1, INV-2, etc.)
- Stated using RFC 2119 keywords
- Falsifiable (can be tested for violation)
- Referenced when rejecting alternatives

Format:
```markdown
### Invariant N — <Short Title>

<Statement using MUST/MUST NOT>

<Brief explanation of why this invariant exists>
```

### 7.2 Design Goal Specification

Design goals describe desired properties without absolute requirements.

Format:
```markdown
### N.N.N <Goal Title>

<Description of the goal>

<Why this goal matters>
```

### 7.3 Non-Goal Specification

Non-goals explicitly exclude concerns from the RFC scope.

Format:
```markdown
### N.N.N <Non-Goal Title>

<What is excluded>

<Why it is excluded or where it is addressed>
```

---

## 8. Rationale Section Requirements

### 8.1 Purpose

The rationale section documents why alternatives were rejected. This prevents
re-litigation of decisions and provides context for future architects.

### 8.2 Required Structure for Each Alternative

Each rejected alternative MUST include:

1. **Description** — What the alternative is
2. **Why It Was Attractive** — Genuine benefits considered
3. **Why It Was Rejected** — Specific failures or violations
4. **Invariants Violated** — Reference to specific invariants
5. **Conclusion** — Summary judgment

### 8.3 Intellectual Honesty

- Acknowledge genuine benefits of rejected alternatives
- Explain context where alternatives might be appropriate
- Avoid dismissive language
- Document if alternative was actually tried

---

## 9. Glossary Requirements

### 9.1 Term Definitions

Each term MUST include:
- The term in bold
- A concise definition
- Qualification "as used in this RFC" where meaning differs from common usage

### 9.2 ADR Index

Document all significant decisions with:
- Decision identifier (ADR-NNN)
- Decision summary
- Rationale reference
- Defining section reference

### 9.3 Diagram Index

List all diagrams with:
- Diagram name
- Diagram type
- Section location

---

## 10. Reference Requirements

### 10.1 Reference Categories

Organize references into:

1. **Normative References** — Required for implementation
2. **Technology Documentation** — Tools and systems referenced
3. **Informative References** — Background and context
4. **Internal References** — Other organizational documents

### 10.2 Citation Format

```
[ABBREV] Author(s), "Title", Publication, Date.
<URL>
```

### 10.3 Internal Reference Format

```
[INTERNAL-ID] Team, "Document Title", Internal Documentation.
`path/to/document.md`
```

---

## 11. Review and Approval

### 11.1 Review Checklist

Before submitting for review, verify:

- [ ] RFC identifier is unique and properly formatted
- [ ] All required sections are present
- [ ] No implementation code or timelines included
- [ ] All invariants are numbered and use RFC 2119 keywords
- [ ] All assumptions are explicitly stated
- [ ] Rationale section documents all considered alternatives
- [ ] Glossary defines all domain-specific terms
- [ ] All diagrams are indexed
- [ ] Navigation links are correct
- [ ] Content is original (not copied from other RFCs)

### 11.2 Reviewer Responsibilities

Reviewers SHOULD verify:

- Technical accuracy
- Completeness of invariants
- Adequacy of rationale
- Clarity of expression
- Adherence to these standards

---

## 12. Maintenance

### 12.1 RFC Updates

When updating an RFC:
- Increment the version number
- Update the "Last Updated" date
- Document changes in version history
- Maintain backward compatibility where possible

### 12.2 RFC Supersession

When an RFC is superseded:
- Change status to "Superseded"
- Reference the superseding RFC
- Do not delete the original

---

## References

[RFC2119] Bradner, S., "Key words for use in RFCs to Indicate Requirement
Levels", BCP 14, RFC 2119, March 1997.
<https://datatracker.ietf.org/doc/html/rfc2119>

[RFC8174] Leiba, B., "Ambiguity of Uppercase vs Lowercase in RFC 2119 Key
Words", BCP 14, RFC 8174, May 2017.
<https://datatracker.ietf.org/doc/html/rfc8174>

[IETF-STYLE] IETF, "RFC Style Guide", RFC 7322, September 2014.
<https://datatracker.ietf.org/doc/html/rfc7322>

---

*End of RFC Authoring Standards*
