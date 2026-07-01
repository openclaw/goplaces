.PHONY: lint test coverage
.PHONY: e2e goplaces force

GOLANGCI_LINT_VERSION ?= v2.11.4
GOLANGCI_LINT ?= go run github.com/golangci/golangci-lint/v2/cmd/golangci-lint@$(GOLANGCI_LINT_VERSION)

lint:
	$(GOLANGCI_LINT) fmt
	$(GOLANGCI_LINT) run ./...

test:
	go test ./...

coverage:
	./scripts/check-coverage.sh

e2e:
	go test -tags=e2e ./... -run TestE2E

goplaces: force
	go build -o goplaces ./cmd/goplaces

force:
