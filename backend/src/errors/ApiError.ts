export type ApiErrorCode = | 'VALIDATION_ERROR'
  | 'INVALID_CREDENTIALS'
  | 'EMAIL_ALREADY_EXISTS'
  | 'EMAIL_NOT_VERIFIED'
  | 'INVALID_VERIFICATION_CODE'
  | 'VERIFICATION_EXPIRED'
  | 'RATE_LIMITED'
  | 'SERVICE_UNAVAILABLE'
  | 'UNAUTHORIZED'
  | 'NOT_FOUND'
  | 'INTERNAL_ERROR';

/**
 * A typed error carrying the HTTP status and a machine-readable code, so
 * the error-handling middleware can serialize it into a uniform response
 * schema (`{ error: { code, message } }`) instead of each route shaping
 * its own error JSON.
 */
export class ApiError extends Error {
  readonly statusCode: number;

  readonly code: ApiErrorCode;

  constructor(statusCode: number, code: ApiErrorCode, message: string) {
    super(message);
    this.name = 'ApiError';
    this.statusCode = statusCode;
    this.code = code;
  }

  static validation(message: string): ApiError {
    return new ApiError(400, 'VALIDATION_ERROR', message);
  }

  static invalidCredentials(): ApiError {
    return new ApiError(401, 'INVALID_CREDENTIALS', 'Invalid email or password');
  }

  static emailAlreadyExists(): ApiError {
    return new ApiError(409, 'EMAIL_ALREADY_EXISTS', 'An account with that email already exists');
  }

  static emailNotVerified(): ApiError {
    return new ApiError(403, 'EMAIL_NOT_VERIFIED', 'Verify your email before signing in');
  }

  static invalidVerificationCode(): ApiError {
    return new ApiError(400, 'INVALID_VERIFICATION_CODE', 'That verification code is invalid');
  }

  static verificationExpired(): ApiError {
    return new ApiError(400, 'VERIFICATION_EXPIRED', 'That verification code has expired');
  }

  static rateLimited(message: string): ApiError {
    return new ApiError(429, 'RATE_LIMITED', message);
  }

  static serviceUnavailable(message: string): ApiError {
    return new ApiError(503, 'SERVICE_UNAVAILABLE', message);
  }

  static unauthorized(message: string): ApiError {
    return new ApiError(401, 'UNAUTHORIZED', message);
  }

  static notFound(message: string): ApiError {
    return new ApiError(404, 'NOT_FOUND', message);
  }
}
