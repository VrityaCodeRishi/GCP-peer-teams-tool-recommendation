VENV?=.venv

.PHONY: init fmt lint run-sample

init:
	python3 -m venv $(VENV)
	$(VENV)/bin/pip install --upgrade pip
	$(VENV)/bin/pip install -r requirements.txt

run-sample:
	${VENV}/bin/python src/recommendation_engine/pipeline.py --sample-data data/sample_logs.csv --project-id sample-project
