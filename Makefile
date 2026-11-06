.PHONY: help verify verify-syntax verify-devcontainer verify-whitelist verify-sandbox verify-firewall test build rebuild clean clean-artifacts

STARTER_NAME := nodejs-typescript
TEST_CMD := npm test
CLEAN_PATHS := node_modules dist

help:
	@echo "Targets:"
	@echo "  verify              Run all security checks"
	@echo "  verify-syntax       JSON, bash syntax, devcontainer runArgs, whitelist consistency"
	@echo "  verify-devcontainer Check devcontainer.json runArgs and postStartCommand"
	@echo "  verify-whitelist    Check sandbox and init-firewall whitelist consistency"
	@echo "  verify-sandbox      Check that the sandbox blocks cat .env (requires Docker)"
	@echo "  verify-firewall     Check the devcontainer firewall (inside the container only)"
	@echo "  test                Run unit tests"
	@echo "  build               Build the Docker image"
	@echo "  rebuild             Rebuild without cache"
	@echo "  clean               Remove containers and volumes (build artifacts: 'make clean-artifacts')"
	@echo "  clean-artifacts     Delete local build/dependency artifacts ($(CLEAN_PATHS))"

verify: verify-syntax
	@echo ""
	@echo "=== Verify $(STARTER_NAME) ==="
	@if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then \
		$(MAKE) --no-print-directory verify-sandbox; \
	else \
		if [ "$${CI:-}" = "true" ]; then \
			echo "FAIL: Docker is not running; fatal in CI."; \
			exit 1; \
		else \
			echo "SKIP: Docker is not running. Only syntax checks were run."; \
		fi; \
	fi
	@echo ""
	@echo "=== Verify complete ==="

verify-syntax:
	@echo "=== Syntax checks ==="
	@python3 -m json.tool < .claude/settings.json > /dev/null && echo "OK: .claude/settings.json valid"
	@python3 -m json.tool < .claude/settings.local.json.example > /dev/null && echo "OK: .claude/settings.local.json.example valid"
	@python3 -m json.tool < .devcontainer/devcontainer.json > /dev/null && echo "OK: .devcontainer/devcontainer.json valid"
	@bash -n .devcontainer/init-firewall.sh && echo "OK: init-firewall.sh syntax valid"
	@bash -n tests/sandbox-leak.test.sh && echo "OK: tests/sandbox-leak.test.sh syntax valid"
	@bash -n tests/firewall.test.sh && echo "OK: tests/firewall.test.sh syntax valid"
	@bash -n tests/validate-devcontainer.sh && echo "OK: tests/validate-devcontainer.sh syntax valid"
	@bash -n tests/validate-whitelist.sh && echo "OK: tests/validate-whitelist.sh syntax valid"
	@$(MAKE) --no-print-directory verify-devcontainer
	@$(MAKE) --no-print-directory verify-whitelist

verify-devcontainer:
	@bash tests/validate-devcontainer.sh

verify-whitelist:
	@bash tests/validate-whitelist.sh

verify-sandbox:
	@echo ""
	@echo "=== Sandbox leak test ==="
	@bash tests/sandbox-leak.test.sh

verify-firewall:
	@echo ""
	@echo "=== Firewall test ==="
	@bash tests/firewall.test.sh

test:
	@$(TEST_CMD)

build:
	@docker compose build

rebuild:
	@docker compose build --no-cache

clean:
	@docker compose down -v 2>/dev/null || true

clean-artifacts:
	@for path in $(CLEAN_PATHS); do \
		if [ -e "$$path" ]; then \
			echo "Deleting $$path"; \
			rm -r -- "$$path"; \
		fi; \
	done
