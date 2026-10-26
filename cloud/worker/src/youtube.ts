export async function youtubeControl<T>(
  operation: 'start' | 'stop',
  body: unknown,
): Promise<T> {
  const secret = process.env.WORKER_API_SECRET ?? '';
  if (secret.length < 32) {
    throw new Error(
      'YouTube is not configured: set WORKER_API_SECRET on backend and worker.',
    );
  }
  const base = process.env.BACKEND_INTERNAL_URL ?? 'http://api:4000';
  const response = await fetch(`${base}/api/v1/youtube/internal/${operation}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'X-Worker-Secret': secret },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(90000),
  });
  const result = (await response.json()) as T & {
    error?: { message?: string };
  };
  if (!response.ok) throw new Error(result.error?.message ?? 'YouTube setup failed.');
  return result;
}
