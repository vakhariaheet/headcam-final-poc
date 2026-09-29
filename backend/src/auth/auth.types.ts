import type { AppUser } from '../types';

export interface SignupRequestBody {
  email: string;
  password: string;
  firstName: string;
  lastName?: string;
}

export interface LoginRequestBody {
  email: string;
  password: string;
}

export interface AuthResult {
  token: string;
  user: AppUser;
}

export interface SignupChallengeResult {
  verificationToken: string;
  email: string;
  expiresInSeconds: number;
  developmentCode?: string;
}

export interface VerifyEmailRequestBody {
  verificationToken: string;
  code: string;
}

export interface ResendVerificationRequestBody {
  verificationToken: string;
}
