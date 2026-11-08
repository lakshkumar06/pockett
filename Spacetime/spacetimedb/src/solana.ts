/** Deterministic validation shared by the database and renderer. No RPC or signing. */
export type SolanaPayment = { recipient: string; amount: string };
export function validateSolanaPayment(value: unknown): asserts value is SolanaPayment {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw Error('Invalid Solana payment');
  const payment = value as SolanaPayment;
  if (Object.keys(payment).some(key => !['recipient', 'amount'].includes(key))) throw Error('Unknown Solana payment field');
  const alphabet = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';
  if (typeof payment.recipient !== 'string' || !/^[1-9A-HJ-NP-Za-km-z]{32,44}$/.test(payment.recipient)) throw Error('Invalid Solana recipient');
  let number = 0n;
  for (const character of payment.recipient) number = number * 58n + BigInt(alphabet.indexOf(character));
  let bytes = 0;
  while (number > 0n) { bytes++; number >>= 8n; }
  bytes += payment.recipient.match(/^1*/)?.[0].length ?? 0;
  if (bytes !== 32 || payment.recipient === '1'.repeat(32)) throw Error('Invalid Solana recipient');
  if (typeof payment.amount !== 'string' || !/^(0|[1-9][0-9]{0,8})(\.[0-9]{1,9})?$/.test(payment.amount) || !/[1-9]/.test(payment.amount)) throw Error('Use a positive SOL amount with at most nine decimals');
}

export function solanaPayURL(payment: SolanaPayment, label: string): string {
  validateSolanaPayment(payment);
  return `solana:${payment.recipient}?amount=${payment.amount}&label=${encodeURIComponent(label)}`;
}
