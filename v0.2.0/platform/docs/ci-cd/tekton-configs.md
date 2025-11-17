# Tekton Pipeline Configurations

## Directory Structure
```
tekton/
├── tasks/
│   ├── git-clone.yaml
│   ├── detect-changes.yaml
│   ├── lint.yaml
│   ├── test.yaml
│   ├── build-image.yaml
│   ├── scan-image.yaml
│   ├── build-package.yaml
│   ├── version.yaml
│   └── update-gitops.yaml
├── pipelines/
│   ├── pr-validation.yaml
│   ├── alpha-build.yaml
│   ├── beta-build.yaml
│   └── stable-release.yaml
├── triggers/
│   ├── eventlistener.yaml
│   ├── triggerbinding-pr.yaml
│   ├── triggerbinding-push.yaml
│   └── triggertemplate.yaml
└── secrets/
    ├── github-secret.yaml
    ├── harbor-secret.yaml
    └── verdaccio-secret.yaml
```

---

## 1. EventListener Configuration

```yaml
# tekton/triggers/eventlistener.yaml
apiVersion: triggers.tekton.dev/v1beta1
kind: EventListener
metadata:
  name: github-listener
  namespace: tekton-pipelines
spec:
  serviceAccountName: tekton-triggers-sa
  triggers:
    # Trigger for PR events
    - name: pull-request
      interceptors:
        - name: "GitHub PR Filter"
          ref:
            name: "github"
          params:
            - name: "secretRef"
              value:
                secretName: github-secret
                secretKey: secretToken
            - name: "eventTypes"
              value: ["pull_request"]
        - name: "CEL Filter"
          ref:
            name: "cel"
          params:
            - name: "filter"
              value: "body.action in ['opened', 'synchronize', 'reopened']"
            - name: "overlays"
              value:
                - key: pr_number
                  expression: "body.pull_request.number"
                - key: short_sha
                  expression: "body.pull_request.head.sha.truncate(7)"
                - key: branch
                  expression: "body.pull_request.head.ref"
      bindings:
        - ref: github-pr-binding
      template:
        ref: pr-validation-template
    
    # Trigger for push to develop
    - name: push-develop
      interceptors:
        - name: "GitHub Push Filter"
          ref:
            name: "github"
          params:
            - name: "secretRef"
              value:
                secretName: github-secret
                secretKey: secretToken
            - name: "eventTypes"
              value: ["push"]
        - name: "CEL Filter"
          ref:
            name: "cel"
          params:
            - name: "filter"
              value: "body.ref == 'refs/heads/develop'"
      bindings:
        - ref: github-push-binding
      template:
        ref: alpha-build-template
    
    # Trigger for release branches
    - name: push-release
      interceptors:
        - name: "GitHub Push Filter"
          ref:
            name: "github"
          params:
            - name: "secretRef"
              value:
                secretName: github-secret
                secretKey: secretToken
            - name: "eventTypes"
              value: ["push"]
        - name: "CEL Filter"
          ref:
            name: "cel"
          params:
            - name: "filter"
              value: "body.ref.startsWith('refs/heads/release/')"
      bindings:
        - ref: github-release-binding
      template:
        ref: beta-build-template
    
    # Trigger for tags on main
    - name: tag-main
      interceptors:
        - name: "GitHub Tag Filter"
          ref:
            name: "github"
          params:
            - name: "secretRef"
              value:
                secretName: github-secret
                secretKey: secretToken
            - name: "eventTypes"
              value: ["create"]
        - name: "CEL Filter"
          ref:
            name: "cel"
          params:
            - name: "filter"
              value: "body.ref_type == 'tag' && body.ref.matches('^v[0-9]+\\.[0-9]+\\.[0-9]+$')"
      bindings:
        - ref: github-tag-binding
      template:
        ref: stable-release-template
---
apiVersion: v1
kind: Service
metadata:
  name: el-github-listener
  namespace: tekton-pipelines
spec:
  type: LoadBalancer
  ports:
    - port: 8080
      targetPort: 8080
  selector:
    eventlistener: github-listener
```

---

## 2. TriggerBindings

```yaml
# tekton/triggers/triggerbinding-pr.yaml
apiVersion: triggers.tekton.dev/v1beta1
kind: TriggerBinding
metadata:
  name: github-pr-binding
  namespace: tekton-pipelines
spec:
  params:
    - name: gitrepositoryurl
      value: $(body.repository.clone_url)
    - name: gitrevision
      value: $(body.pull_request.head.sha)
    - name: pr-number
      value: $(extensions.pr_number)
    - name: short-sha
      value: $(extensions.short_sha)
    - name: branch
      value: $(extensions.branch)
    - name: base-branch
      value: $(body.pull_request.base.ref)
---
# tekton/triggers/triggerbinding-push.yaml
apiVersion: triggers.tekton.dev/v1beta1
kind: TriggerBinding
metadata:
  name: github-push-binding
  namespace: tekton-pipelines
spec:
  params:
    - name: gitrepositoryurl
      value: $(body.repository.clone_url)
    - name: gitrevision
      value: $(body.after)
    - name: branch
      value: $(body.ref)
```

---

## 3. TriggerTemplates

```yaml
# tekton/triggers/triggertemplate-pr.yaml
apiVersion: triggers.tekton.dev/v1beta1
kind: TriggerTemplate
metadata:
  name: pr-validation-template
  namespace: tekton-pipelines
spec:
  params:
    - name: gitrepositoryurl
    - name: gitrevision
    - name: pr-number
    - name: short-sha
    - name: branch
    - name: base-branch
  resourcetemplates:
    - apiVersion: tekton.dev/v1beta1
      kind: PipelineRun
      metadata:
        generateName: pr-validation-
        namespace: tekton-pipelines
        labels:
          tekton.dev/pipeline: pr-validation
          pr-number: $(tt.params.pr-number)
      spec:
        pipelineRef:
          name: pr-validation
        params:
          - name: repo-url
            value: $(tt.params.gitrepositoryurl)
          - name: revision
            value: $(tt.params.gitrevision)
          - name: pr-number
            value: $(tt.params.pr-number)
          - name: short-sha
            value: $(tt.params.short-sha)
          - name: image-tag
            value: pr-$(tt.params.pr-number)-$(tt.params.short-sha)
        workspaces:
          - name: shared-data
            volumeClaimTemplate:
              spec:
                accessModes:
                  - ReadWriteOnce
                resources:
                  requests:
                    storage: 5Gi
          - name: harbor-credentials
            secret:
              secretName: harbor-secret
          - name: github-credentials
            secret:
              secretName: github-secret
```

---

## 4. PR Validation Pipeline

```yaml
# tekton/pipelines/pr-validation.yaml
apiVersion: tekton.dev/v1beta1
kind: Pipeline
metadata:
  name: pr-validation
  namespace: tekton-pipelines
spec:
  params:
    - name: repo-url
      type: string
    - name: revision
      type: string
    - name: pr-number
      type: string
    - name: short-sha
      type: string
    - name: image-tag
      type: string
  
  workspaces:
    - name: shared-data
    - name: harbor-credentials
    - name: github-credentials
  
  tasks:
    # 1. Clone repository
    - name: fetch-source
      taskRef:
        name: git-clone
        kind: ClusterTask
      workspaces:
        - name: output
          workspace: shared-data
      params:
        - name: url
          value: $(params.repo-url)
        - name: revision
          value: $(params.revision)
    
    # 2. Detect changed services in monorepo
    - name: detect-changes
      runAfter: ["fetch-source"]
      taskRef:
        name: detect-changes
      workspaces:
        - name: source
          workspace: shared-data
      params:
        - name: base-revision
          value: origin/develop
    
    # 3. Lint code
    - name: lint
      runAfter: ["detect-changes"]
      taskRef:
        name: lint
      workspaces:
        - name: source
          workspace: shared-data
      params:
        - name: changed-services
          value: $(tasks.detect-changes.results.services)
    
    # 4. Run unit tests
    - name: unit-tests
      runAfter: ["lint"]
      taskRef:
        name: unit-tests
      workspaces:
        - name: source
          workspace: shared-data
      params:
        - name: changed-services
          value: $(tasks.detect-changes.results.services)
    
    # 5. Build container images
    - name: build-images
      runAfter: ["unit-tests"]
      taskRef:
        name: build-image
      workspaces:
        - name: source
          workspace: shared-data
        - name: dockerconfig
          workspace: harbor-credentials
      params:
        - name: changed-services
          value: $(tasks.detect-changes.results.services)
        - name: IMAGE_TAG
          value: $(params.image-tag)
        - name: REGISTRY
          value: harbor.yourdomain.com/services
    
    # 6. Scan images for vulnerabilities
    - name: scan-images
      runAfter: ["build-images"]
      taskRef:
        name: trivy-scan
      params:
        - name: images
          value: $(tasks.build-images.results.images)
        - name: severity
          value: "HIGH,CRITICAL"
    
    # 7. Deploy preview environment
    - name: deploy-preview
      runAfter: ["scan-images"]
      when:
        - input: "$(tasks.scan-images.results.scan-status)"
          operator: in
          values: ["passed"]
      taskRef:
        name: deploy-preview
      workspaces:
        - name: source
          workspace: shared-data
      params:
        - name: pr-number
          value: $(params.pr-number)
        - name: images
          value: $(tasks.build-images.results.images)
        - name: changed-services
          value: $(tasks.detect-changes.results.services)
    
    # 8. Comment on PR with results
    - name: comment-pr
      runAfter: ["deploy-preview"]
      taskRef:
        name: github-comment
      workspaces:
        - name: github-credentials
          workspace: github-credentials
      params:
        - name: pr-number
          value: $(params.pr-number)
        - name: preview-url
          value: $(tasks.deploy-preview.results.preview-url)
        - name: scan-results
          value: $(tasks.scan-images.results.scan-report)
    
    # 9. Handle vulnerabilities
    - name: request-changes
      runAfter: ["scan-images"]
      when:
        - input: "$(tasks.scan-images.results.scan-status)"
          operator: in
          values: ["failed"]
      taskRef:
        name: github-request-changes
      workspaces:
        - name: github-credentials
          workspace: github-credentials
      params:
        - name: pr-number
          value: $(params.pr-number)
        - name: scan-results
          value: $(tasks.scan-images.results.scan-report)
```

---

## 5. Alpha Build Pipeline (Develop Merge)

```yaml
# tekton/pipelines/alpha-build.yaml
apiVersion: tekton.dev/v1beta1
kind: Pipeline
metadata:
  name: alpha-build
  namespace: tekton-pipelines
spec:
  params:
    - name: repo-url
      type: string
    - name: revision
      type: string
  
  workspaces:
    - name: shared-data
    - name: harbor-credentials
    - name: verdaccio-credentials
    - name: github-credentials
  
  tasks:
    # 1. Clone repository
    - name: fetch-source
      taskRef:
        name: git-clone
        kind: ClusterTask
      workspaces:
        - name: output
          workspace: shared-data
      params:
        - name: url
          value: $(params.repo-url)
        - name: revision
          value: $(params.revision)
    
    # 2. Auto-version (alpha)
    - name: auto-version
      runAfter: ["fetch-source"]
      taskRef:
        name: auto-version
      workspaces:
        - name: source
          workspace: shared-data
      params:
        - name: maturity
          value: "alpha"
    
    # 3. Detect changed services
    - name: detect-changes
      runAfter: ["auto-version"]
      taskRef:
        name: detect-changes
      workspaces:
        - name: source
          workspace: shared-data
      params:
        - name: base-revision
          value: HEAD~1
    
    # 4. Build container images
    - name: build-images
      runAfter: ["detect-changes"]
      taskRef:
        name: build-image
      workspaces:
        - name: source
          workspace: shared-data
        - name: dockerconfig
          workspace: harbor-credentials
      params:
        - name: changed-services
          value: $(tasks.detect-changes.results.services)
        - name: IMAGE_TAG
          value: $(tasks.auto-version.results.version)
        - name: REGISTRY
          value: harbor.yourdomain.com/services
    
    # 5. Build TypeScript packages
    - name: build-packages
      runAfter: ["detect-changes"]
      taskRef:
        name: build-packages
      workspaces:
        - name: source
          workspace: shared-data
        - name: npm-credentials
          workspace: verdaccio-credentials
      params:
        - name: changed-packages
          value: $(tasks.detect-changes.results.packages)
        - name: VERSION
          value: $(tasks.auto-version.results.version)
    
    # 6. Scan images
    - name: scan-images
      runAfter: ["build-images"]
      taskRef:
        name: trivy-scan
      params:
        - name: images
          value: $(tasks.build-images.results.images)
        - name: severity
          value: "HIGH,CRITICAL"
    
    # 7. Publish to Harbor (with multiple tags)
    - name: publish-images
      runAfter: ["scan-images"]
      when:
        - input: "$(tasks.scan-images.results.scan-status)"
          operator: in
          values: ["passed"]
      taskRef:
        name: publish-images
      workspaces:
        - name: dockerconfig
          workspace: harbor-credentials
      params:
        - name: images
          value: $(tasks.build-images.results.images)
        - name: version
          value: $(tasks.auto-version.results.version)
        - name: tags
          value: ["alpha", "latest-alpha", "$(tasks.auto-version.results.version)"]
    
    # 8. Publish packages to Verdaccio
    - name: publish-packages
      runAfter: ["build-packages"]
      taskRef:
        name: publish-packages
      workspaces:
        - name: source
          workspace: shared-data
        - name: npm-credentials
          workspace: verdaccio-credentials
      params:
        - name: version
          value: $(tasks.auto-version.results.version)
    
    # 9. Create Git tag
    - name: create-tag
      runAfter: ["publish-images", "publish-packages"]
      taskRef:
        name: git-tag
      workspaces:
        - name: source
          workspace: shared-data
        - name: github-credentials
          workspace: github-credentials
      params:
        - name: tag
          value: $(tasks.auto-version.results.version)
    
    # 10. Update GitOps config repo
    - name: update-gitops
      runAfter: ["create-tag"]
      taskRef:
        name: update-gitops-repo
      workspaces:
        - name: github-credentials
          workspace: github-credentials
      params:
        - name: config-repo
          value: https://github.com/yourorg/gitops-config.git
        - name: version
          value: $(tasks.auto-version.results.version)
        - name: images
          value: $(tasks.build-images.results.images)
        - name: environment
          value: "dev"
```

---

## 6. Key Tasks

### Detect Changes Task (Monorepo)

```yaml
# tekton/tasks/detect-changes.yaml
apiVersion: tekton.dev/v1beta1
kind: Task
metadata:
  name: detect-changes
  namespace: tekton-pipelines
spec:
  params:
    - name: base-revision
      type: string
      description: Base revision to compare against
      default: "origin/develop"
  
  workspaces:
    - name: source
  
  results:
    - name: services
      description: List of changed services
    - name: packages
      description: List of changed packages
  
  steps:
    - name: detect
      image: alpine/git
      workingDir: $(workspaces.source.path)
      script: |
        #!/bin/sh
        set -e
        
        # Get changed files
        CHANGED_FILES=$(git diff --name-only $(params.base-revision) HEAD)
        
        # Detect changed services
        SERVICES=$(echo "$CHANGED_FILES" | grep "^services/" | cut -d'/' -f2 | sort -u | tr '\n' ',')
        echo -n "$SERVICES" | tee $(results.services.path)
        
        # Detect changed packages
        PACKAGES=$(echo "$CHANGED_FILES" | grep "^packages/" | cut -d'/' -f2 | sort -u | tr '\n' ',')
        echo -n "$PACKAGES" | tee $(results.packages.path)
        
        echo "Changed services: $SERVICES"
        echo "Changed packages: $PACKAGES"
```

### Auto Version Task

```yaml
# tekton/tasks/version.yaml
apiVersion: tekton.dev/v1beta1
kind: Task
metadata:
  name: auto-version
  namespace: tekton-pipelines
spec:
  params:
    - name: maturity
      type: string
      description: "Maturity level: alpha, beta, or stable"
      default: "alpha"
  
  workspaces:
    - name: source
  
  results:
    - name: version
      description: Generated version string
  
  steps:
    - name: generate-version
      image: alpine
      workingDir: $(workspaces.source.path)
      script: |
        #!/bin/sh
        set -e
        
        # Read current version from package.json or VERSION file
        CURRENT_VERSION=$(cat VERSION || echo "1.0.0")
        
        # Extract major.minor.patch
        MAJOR=$(echo $CURRENT_VERSION | cut -d. -f1)
        MINOR=$(echo $CURRENT_VERSION | cut -d. -f2)
        PATCH=$(echo $CURRENT_VERSION | cut -d. -f3)
        
        # Generate version based on maturity
        case "$(params.maturity)" in
          alpha)
            TIMESTAMP=$(date +%Y%m%d%H%M%S)
            VERSION="v${MAJOR}.${MINOR}.${PATCH}-alpha.${TIMESTAMP}"
            ;;
          beta)
            # Increment beta counter
            BETA_COUNT=$(git tag -l "v${MAJOR}.${MINOR}.${PATCH}-beta.*" | wc -l)
            BETA_COUNT=$((BETA_COUNT + 1))
            VERSION="v${MAJOR}.${MINOR}.${PATCH}-beta.${BETA_COUNT}"
            ;;
          stable)
            VERSION="v${MAJOR}.${MINOR}.${PATCH}"
            ;;
        esac
        
        echo -n "$VERSION" | tee $(results.version.path)
        echo "Generated version: $VERSION"
```

### Build Image Task (with Kaniko)

```yaml
# tekton/tasks/build-image.yaml
apiVersion: tekton.dev/v1beta1
kind: Task
metadata:
  name: build-image
  namespace: tekton-pipelines
spec:
  params:
    - name: changed-services
      type: string
    - name: IMAGE_TAG
      type: string
    - name: REGISTRY
      type: string
  
  workspaces:
    - name: source
    - name: dockerconfig
  
  results:
    - name: images
      description: Built image references
  
  steps:
    - name: build
      image: gcr.io/kaniko-project/executor:latest
      workingDir: $(workspaces.source.path)
      env:
        - name: DOCKER_CONFIG
          value: /tekton/home/.docker
      script: |
        #!/busybox/sh
        set -e
        
        IMAGES=""
        
        # Loop through changed services
        IFS=',' read -ra SERVICES <<< "$(params.changed-services)"
        for SERVICE in "${SERVICES[@]}"; do
          if [ -d "services/$SERVICE" ]; then
            IMAGE_NAME="$(params.REGISTRY)/${SERVICE}:$(params.IMAGE_TAG)"
            
            /kaniko/executor \
              --context=services/$SERVICE \
              --dockerfile=services/$SERVICE/Dockerfile \
              --destination=$IMAGE_NAME \
              --cache=true \
              --cache-repo=$(params.REGISTRY)/cache
            
            IMAGES="${IMAGES}${IMAGE_NAME},"
          fi
        done
        
        # Remove trailing comma
        IMAGES=${IMAGES%,}
        echo -n "$IMAGES" | tee $(results.images.path)
      volumeMounts:
        - name: docker-config
          mountPath: /tekton/home/.docker
  
  volumes:
    - name: docker-config
      secret:
        secretName: harbor-secret
```

### Trivy Scan Task

```yaml
# tekton/tasks/scan-image.yaml
apiVersion: tekton.dev/v1beta1
kind: Task
metadata:
  name: trivy-scan
  namespace: tekton-pipelines
spec:
  params:
    - name: images
      type: string
    - name: severity
      type: string
      default: "HIGH,CRITICAL"
  
  results:
    - name: scan-status
      description: "passed or failed"
    - name: scan-report
      description: Vulnerability scan report
  
  steps:
    - name: scan
      image: aquasec/trivy:latest
      script: |
        #!/bin/sh
        set -e
        
        SCAN_STATUS="passed"
        REPORT=""
        
        IFS=',' read -ra IMAGES <<< "$(params.images)"
        for IMAGE in "${IMAGES[@]}"; do
          echo "Scanning $IMAGE..."
          
          # Run Trivy scan
          trivy image \
            --severity $(params.severity) \
            --exit-code 1 \
            --format json \
            --output /tmp/scan-${IMAGE//\//-}.json \
            $IMAGE || SCAN_STATUS="failed"
          
          # Append to report
          REPORT="${REPORT}\n$(cat /tmp/scan-${IMAGE//\//-}.json)"
        done
        
        echo -n "$SCAN_STATUS" | tee $(results.scan-status.path)
        echo -n "$REPORT" | tee $(results.scan-report.path)
```

---

## 7. Secrets Configuration

```yaml
# tekton/secrets/harbor-secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: harbor-secret
  namespace: tekton-pipelines
type: kubernetes.io/dockerconfigjson
data:
  .dockerconfigjson: <base64-encoded-docker-config>
---
# tekton/secrets/github-secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: github-secret
  namespace: tekton-pipelines
type: Opaque
stringData:
  token: <github-personal-access-token>
  secretToken: <webhook-secret>
---
# tekton/secrets/verdaccio-secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: verdaccio-secret
  namespace: tekton-pipelines
type: Opaque
stringData:
  .npmrc: |
    //verdaccio.yourdomain.com/:_authToken=<token>
```

---

## 8. ServiceAccount for Tekton

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: tekton-triggers-sa
  namespace: tekton-pipelines
secrets:
  - name: github-secret
  - name: harbor-secret
  - name: verdaccio-secret
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: tekton-triggers-admin
subjects:
  - kind: ServiceAccount
    name: tekton-triggers-sa
    namespace: tekton-pipelines
roleRef:
  kind: ClusterRole
  name: tekton-triggers-eventlistener-roles
  apiGroup: rbac.authorization.k8s.io
```

---

This Tekton configuration provides:
- ✅ Automatic PR validation with preview deployments
- ✅ Alpha builds on develop merge with timestamp versioning
- ✅ Beta builds on release branches
- ✅ Vulnerability scanning with Harbor/Trivy
- ✅ Monorepo change detection
- ✅ Multi-tag image publishing
- ✅ Package versioning for TypeScript packages
- ✅ GitOps repo updates for Kargo integration
