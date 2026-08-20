class RequestContext {
  const RequestContext({
    required this.requestId,
    this.correlationId,
    this.idempotencyKey,
    this.operationId,
  });

  final String requestId;
  final String? correlationId;
  final String? idempotencyKey;
  final String? operationId;
}
