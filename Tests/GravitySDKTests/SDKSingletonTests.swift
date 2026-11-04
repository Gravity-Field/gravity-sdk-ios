import Testing

/// Suites that mutate the SDK singleton must also be serialized with each other.
@Suite(.serialized)
struct SDKSingletonTests {}
