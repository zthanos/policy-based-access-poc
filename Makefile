.PHONY: deploy test clean clean-deploy-test

deploy:
	powershell -ExecutionPolicy Bypass -File scripts/deploy.ps1

test:
	powershell -ExecutionPolicy Bypass -File scripts/test.ps1

clean:
	powershell -ExecutionPolicy Bypass -File scripts/clean.ps1

clean-deploy-test: clean deploy test
