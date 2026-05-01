.PHONY: deploy test clean

deploy:
	powershell -ExecutionPolicy Bypass -File scripts/deploy.ps1

test:
	powershell -ExecutionPolicy Bypass -File scripts/test.ps1

clean:
	powershell -ExecutionPolicy Bypass -File scripts/clean.ps1
