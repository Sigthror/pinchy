override APP_NAME=pinchy
override GO_VERSION=1.15
override DOCKER_BUILDKIT=1

GOOS?=$(shell go env GOOS || echo linux)
GOARCH?=$(shell go env GOARCH || echo amd64)
CGO_ENABLED?=0

BUIlD_VERSION?=latest

DOCKER_REGISTRY?=docker.io
DOCKER_IMAGE?=insidieux/${APP_NAME}
DOCKER_TAG?=latest
DOCKER_USER=
DOCKER_PASSWORD=

ifeq (, $(shell which docker))
$(error "Binary docker not found in $(PATH)")
endif

.PHONY: all
all: cleanup vendor wire lint test build

.PHONY: cleanup
cleanup:
	@rm ${PWD}/bin/${APP_NAME}* || true
	@rm ${PWD}/coverage.out || true
	@find ${PWD} -type f -name "wire_gen.go" -delete
	@find ${PWD} -type f -name "mock_*_test.go" -delete
	@rm -r ${PWD}/vendor || true

.PHONY: vendor
vendor:
	@rm -r ${PWD}/vendor || true
	@docker run --rm -v ${PWD}:/project -w /project golang:${GO_VERSION} go mod tidy
	@docker run --rm -v ${PWD}:/project -w /project golang:${GO_VERSION} go mod vendor

.PHONY: wire
wire:
	@docker build \
		--build-arg GO_VERSION=${GO_VERSION} \
		-f ${PWD}/build/docker/utils/wire/Dockerfile \
		-t wire:custom \
			build/docker/utils/wire
	@find ${PWD} -type f -name "wire_gen.go" -delete
	@docker run --rm \
		-v ${PWD}:/project \
		-w /project \
		wire:custom \
			/project/...

.PHONY: lint-golangci-lint
lint-golangci-lint:
	@docker run --rm \
		-v ${PWD}:/project \
		-w /project \
		golangci/golangci-lint:v1.33.0 \
			golangci-lint run -v

.PHONY: lint-golint
lint-golint:
	@docker build \
		--build-arg GO_VERSION=${GO_VERSION} \
		-f ${PWD}/build/docker/utils/golint/Dockerfile \
		-t golint:custom \
			build/docker/utils/golint
	@docker run --rm \
		-v ${PWD}:/project \
		-w /project \
		golint:custom \
			--set_exit_status \
			/project/pkg/... \
			/project/internal/... \
			/project/cmd/...

.PHONY: lint
lint:
	@make lint-golangci-lint
	@make lint-golint

.PHONY: test
test:
	@rm -r ${PWD}/coverage.out || true
	@docker run --rm \
		-v ${PWD}:/project \
		-w /project \
		golang:${GO_VERSION} \
			go test \
				-race \
				-mod vendor \
				-covermode=atomic \
				-coverprofile=/project/coverage.out \
					/project/...

.PHONY: build
build:
	@rm ${PWD}/bin/${APP_NAME} || true
	@docker run --rm \
		-v ${PWD}:/project \
		-w /project \
		-e GOOS=${GOOS} \
		-e GOARCH=${GOARCH} \
		-e CGO_ENABLED=${CGO_ENABLED} \
		-e GO111MODULE=on \
		golang:${GO_VERSION} \
			go build \
				-mod vendor \
				-ldflags "-X main.version=${BUIlD_VERSION}" \
				-o /project/bin/${APP_NAME} \
				-v /project/cmd/${APP_NAME}

.PHONY: docker-image-build
docker-image-build:
ifndef DOCKER_IMAGE
	$(error DOCKER_IMAGE is not set)
endif
ifndef DOCKER_TAG
	$(error DOCKER_TAG is not set)
endif
	@docker rmi ${DOCKER_IMAGE}:${DOCKER_TAG} || true
	@docker build \
		-f ${PWD}/build/docker/cmd/pinchy/Dockerfile \
		-t ${DOCKER_IMAGE}:${DOCKER_TAG} \
			.

.PHONY: docker-image-push
docker-image-push:
ifndef DOCKER_REGISTRY
	$(error DOCKER_REGISTRY is not set)
endif
ifndef DOCKER_USER
	$(error DOCKER_USER is not set)
endif
ifndef DOCKER_PASSWORD
	$(error DOCKER_PASSWORD is not set)
endif
ifndef DOCKER_IMAGE
	$(error DOCKER_IMAGE is not set)
endif
ifndef DOCKER_TAG
	$(error DOCKER_TAG is not set)
endif
	@docker login -u ${DOCKER_USER} -p ${DOCKER_PASSWORD} ${DOCKER_REGISTRY}
	@docker push ${DOCKER_IMAGE}:${DOCKER_TAG}

.PHONY: mockery
mockery:
ifndef MOCKERY_SOURCE_DIR
	$(error MOCKERY_SOURCE_DIR is not set)
endif
	@docker pull vektra/mockery:v2.4.0
	@find ${PWD} -type f -name "mock_*_test.go" -delete
	@docker run \
		--rm \
		-v ${PWD}:/project \
		-w /project \
		vektra/mockery:v2.4.0 \
			--testonly \
			--inpackage \
			--all \
			--dir /project/${MOCKERY_SOURCE_DIR} \
			--output /project/${MOCKERY_SOURCE_DIR} \
			--case snake \
			--log-level trace
