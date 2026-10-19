// Validação e mascaramento de CPF (usado no servidor e espelhado no app).

export function somenteDigitos(valor: unknown): string {
  return String(valor ?? '').replace(/\D/g, '');
}

/** Valida os dígitos verificadores do CPF. */
export function cpfValido(cpf: string): boolean {
  const d = somenteDigitos(cpf);
  if (d.length !== 11) return false;
  if (/^(\d)\1{10}$/.test(d)) return false;

  const digito = (ate: number): number => {
    let soma = 0;
    for (let i = 0; i < ate; i++) {
      soma += parseInt(d[i]) * (ate + 1 - i);
    }
    const resto = (soma * 10) % 11;
    return resto === 10 ? 0 : resto;
  };

  return digito(9) === parseInt(d[9]) && digito(10) === parseInt(d[10]);
}

/** Mascara o CPF para exibição: ***.456.789-** */
export function mascararCpf(cpf: string): string {
  const d = somenteDigitos(cpf);
  if (d.length !== 11) return '***.***.***-**';
  return `***.${d.substring(3, 6)}.${d.substring(6, 9)}-**`;
}
