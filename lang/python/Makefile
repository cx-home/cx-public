PY ?= python3
TEST ?= test.py
TEST_FILE ?= ../test-case.txt


.PHONY: test xml-test ast run clean

test: clean
	$(PY) $(TEST) report $(TEST_FILE) --trace-parse $(if $(CASE),--case $(CASE))

xml-test: clean
	$(PY) $(TEST) xml-report $(TEST_FILE) --trace-parse $(if $(CASE),--case $(CASE))

ast:
	$(PY) $(TEST) ast $(TEST_FILE) $(if $(CASE),--case $(CASE))

run:
	$(PY) $(TEST) pretty $(TEST_FILE) $(if $(CASE),--case $(CASE))

clean:
	rm -f *.pyc __pycache__ -r
