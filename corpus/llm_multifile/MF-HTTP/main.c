#include <stdio.h>
#include <string.h>
#include "http.h"

static const char *const REQUEST_GET =
    "GET /index.html HTTP/1.1\r\n"
    "Host: example.com\r\n"
    "User-Agent: vitro/1.0\r\n"
    "\r\n";

static const char *const REQUEST_POST =
    "POST /submit HTTP/1.1\r\n"
    "Host: example.com\r\n"
    "Content-Length: 11\r\n"
    "Content-Type: text/plain\r\n"
    "\r\n"
    "hello world";

static const char *const RESPONSE_CHUNKED =
    "HTTP/1.1 200 OK\r\n"
    "Server: vitro\r\n"
    "Transfer-Encoding: chunked\r\n"
    "Content-Type: text/html\r\n"
    "\r\n"
    "5\r\n"
    "hello\r\n"
    "0\r\n"
    "\r\n";

static const char *const REQUEST_NO_HOST =
    "GET /missing HTTP/1.1\r\n"
    "User-Agent: vitro/1.0\r\n"
    "\r\n";

static const char *const REQUEST_BAD_LENGTH =
    "POST /submit HTTP/1.1\r\n"
    "Host: example.com\r\n"
    "Content-Length: 100\r\n"
    "\r\n"
    "short";

int main(void)
{
    HttpRequest request;
    HttpResponse response;
    char rebuilt[1024];
    int rc;
    int length;

    printf("=== request without body ===\n");
    rc = http_parse_request(REQUEST_GET, &request);
    printf("  parse rc=%d\n", rc);
    http_print_request(&request);

    printf("=== request with body ===\n");
    rc = http_parse_request(REQUEST_POST, &request);
    printf("  parse rc=%d\n", rc);
    http_print_request(&request);

    printf("=== response with chunked encoding ===\n");
    rc = http_parse_response(RESPONSE_CHUNKED, &response);
    printf("  parse rc=%d\n", rc);
    http_print_response(&response);

    printf("=== rebuild the first request ===\n");
    http_parse_request(REQUEST_GET, &request);
    length = http_build_request(&request, rebuilt, sizeof rebuilt);
    printf("  rebuilt length=%d original length=%d\n", length, (int)strlen(REQUEST_GET));
    printf("  byte_identical=%s\n",
           (length == (int)strlen(REQUEST_GET) && memcmp(rebuilt, REQUEST_GET, (size_t)length) == 0)
               ? "yes" : "no");
    printf("  rebuilt:\n%s", rebuilt);

    printf("=== response rebuild ===\n");
    http_parse_response(RESPONSE_CHUNKED, &response);
    length = http_build_response(&response, rebuilt, sizeof rebuilt);
    printf("  rebuilt length=%d\n", length);

    printf("=== invalid request ===\n");
    rc = http_parse_request(REQUEST_NO_HOST, &request);
    printf("  parse rc=%d error=%s\n", rc, request.error);
    http_print_request(&request);

    printf("=== content length mismatch ===\n");
    rc = http_parse_request(REQUEST_BAD_LENGTH, &request);
    printf("  parse rc=%d error=%s\n", rc, request.error);
    printf("  body_length_reported=%d\n", request.body_length);

    printf("=== status texts ===\n");
    printf("  http_ops=%d\n", http_ops);
    printf("  200=%s 404=%s 500=%s 999=%s\n",
           http_status_text(200), http_status_text(404),
           http_status_text(500), http_status_text(999));
    return 0;
}
