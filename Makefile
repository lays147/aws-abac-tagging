TF := mise exec -- terraform
MODULES := abac my-demo-bucket

.PHONY: fmt init validate plan clean $(MODULES)

fmt:
	$(TF) fmt -recursive

init:
	@for m in $(MODULES); do \
		echo "==> $$m: init"; \
		(cd $$m && $(TF) init -backend=false) || exit 1; \
	done

validate: init
	@for m in $(MODULES); do \
		echo "==> $$m: validate"; \
		(cd $$m && $(TF) validate) || exit 1; \
	done

plan: init
	@for m in $(MODULES); do \
		echo "==> $$m: plan"; \
		(cd $$m && $(TF) plan) || exit 1; \
	done

clean:
	@for m in $(MODULES); do \
		rm -rf $$m/.terraform $$m/.terraform.lock.hcl; \
	done
