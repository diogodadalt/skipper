SOURCES =         $(shell find . -name '*.go')
CURRENT_VERSION = $(shell git tag | sort -V | tail -n1)
VERSION ?=        $(CURRENT_VERSION)
NEXT_MAJOR =      $(shell go run packaging/version/version.go major $(CURRENT_VERSION))
NEXT_MINOR =      $(shell go run packaging/version/version.go minor $(CURRENT_VERSION))
NEXT_PATCH =      $(shell go run packaging/version/version.go patch $(CURRENT_VERSION))
COMMIT_HASH =     $(shell git rev-parse --short HEAD)

default: build

lib: $(SOURCES)
	go build  ./...

bindir:
	mkdir -p bin

skipper: $(SOURCES) bindir
	go build -ldflags "-X main.version=$(VERSION) -X main.commit=$(COMMIT_HASH)" -o bin/skipper ./cmd/skipper

eskip: $(SOURCES) bindir
	go build -ldflags "-X main.version=$(VERSION) -X main.commit=$(COMMIT_HASH)" -o bin/eskip ./cmd/eskip

build: $(SOURCES) lib skipper eskip

install: $(SOURCES)
	go install -ldflags "-X main.version=$(VERSION) -X main.commit=$(COMMIT_HASH)" ./cmd/skipper
	go install -ldflags "-X main.version=$(VERSION) -X main.commit=$(COMMIT_HASH)" ./cmd/eskip

check: build
	go test ./...

shortcheck: build
	go test -test.short -run ^Test ./...

bench: build
	go test -bench . ./...

clean:
	go clean -i ./...

deps:
	go get golang.org/x/sys/unix
	go get golang.org/x/crypto/ssh/terminal
	go get -t github.com/zalando/skipper/...
	./etcd/install.sh
	go get github.com/tools/godep
	godep restore ./...

vet: $(SOURCES)
	go vet ./...

fmt: $(SOURCES)
	@gofmt -w $(SOURCES)

check-fmt: $(SOURCES)
	if [ "$$(gofmt -d $(SOURCES))" != "" ]; then false; else true; fi

precommit: build shortcheck fmt vet

check-precommit: build shortcheck check-fmt vet

tag:
	git tag $(VERSION)

push-tags:
	git push --tags https://$(GITHUB_AUTH)@github.com/zalando/skipper

release-major:
	make VERSION=$(NEXT_MAJOR) tag push-tags
	make -C packaging VERSION=$(NEXT_MAJOR) docker-build docker-push

release-minor:
	make VERSION=$(NEXT_MINOR) tag push-tags
	make -C packaging VERSION=$(NEXT_MINOR) docker-build docker-push

release-patch:
	make VERSION=$(NEXT_PATCH) tag push-tags
	make -C packaging VERSION=$(NEXT_PATCH) docker-build docker-push

ci-user:
	git config --global user.email "builds@travis-ci.com"
	git config --global user.name "Travis CI"

ci-release-major: ci-user deps release-major
ci-release-minor: ci-user deps release-minor
ci-release-patch: ci-user deps release-patch

ci-trigger:
ifeq ($(TRAVIS_BRANCH)_$(TRAVIS_PULL_REQUEST)_$(findstring major-release,$(TRAVIS_COMMIT_MESSAGE)), master_false_major-release)
	make ci-release-major
else ifeq ($(TRAVIS_BRANCH)_$(TRAVIS_PULL_REQUEST)_$(findstring minor-release,$(TRAVIS_COMMIT_MESSAGE)), master_false_minor-release)
	make ci-release-minor
else ifeq ($(TRAVIS_BRANCH)_$(TRAVIS_PULL_REQUEST), master_false)
	make ci-release-patch
else ifeq ($(TRAVIS_BRANCH), master)
	make deps check-precommit
else
	make deps shortcheck
endif
