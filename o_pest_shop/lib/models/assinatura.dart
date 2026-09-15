class Assinatura {
  final int id;
  final String userId;
  final String plano;
  final String status;
  final double? valor;
  final String? dataInicio;
  final String? dataFim;
  final bool bonus;
  final String? createdAt;

  Assinatura({
    required this.id,
    required this.userId,
    this.plano = 'basico',
    this.status = 'ativo',
    this.valor,
    this.dataInicio,
    this.dataFim,
    this.bonus = false,
    this.createdAt,
  });

  bool get isAtivo => status == 'ativo';
  bool get isPremium => plano == 'premium' || plano == 'vip';

  factory Assinatura.fromJson(Map<String, dynamic> json) => Assinatura(
    id: json['id'] as int,
    userId: json['user_id'] as String? ?? '',
    plano: json['plano'] as String? ?? 'basico',
    status: json['status'] as String? ?? 'ativo',
    valor: (json['valor'] as num?)?.toDouble(),
    dataInicio: json['data_inicio'] as String?,
    dataFim: json['data_fim'] as String?,
    bonus: json['bonus'] as bool? ?? false,
    createdAt: json['created_at'] as String?,
  );
}
