# Mock of Cezar and GitHub APIs for E2E. Base image from mirror.gcr.io to avoid
# Docker Hub pull limits in CI.
FROM mirror.gcr.io/library/python:3.12-slim
COPY tests/tools/mock_api.py /mock_api.py
EXPOSE 8080
CMD ["python3", "/mock_api.py", "--port", "8080"]
