import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/helpers/theme_colors.dart';
import '../../../services/frete_service.dart';

class UnidadeFormScreen extends StatefulWidget {
  final Map<String, dynamic>? unidade;
  final bool modoParceiro;
  const UnidadeFormScreen({super.key, this.unidade, this.modoParceiro = false});

  @override
  State<UnidadeFormScreen> createState() => _UnidadeFormScreenState();
}

class _UnidadeFormScreenState extends State<UnidadeFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nomeCtrl = TextEditingController();
  final _enderecoCtrl = TextEditingController();
  final _cepCtrl = TextEditingController();
  final _bairroCtrl = TextEditingController();
  final _cidadeCtrl = TextEditingController();
  final _horarioSegCtrl = TextEditingController();
  final _horarioTerCtrl = TextEditingController();
  final _horarioQuaCtrl = TextEditingController();
  final _horarioQuiCtrl = TextEditingController();
  final _horarioSexCtrl = TextEditingController();
  final _horarioSabCtrl = TextEditingController();
  final _horarioDomCtrl = TextEditingController();
  final _ordemCtrl = TextEditingController();
  final _distanciaCtrl = TextEditingController();
  final _taxaCtrl = TextEditingController();
  final _freteGratisAcimaCtrl = TextEditingController();
  final _cnpjCtrl = TextEditingController();
  final _inscricaoEstadualCtrl = TextEditingController();
  final _nomeRemetenteCtrl = TextEditingController();
  final _numeroCtrl = TextEditingController();
  final _complementoCtrl = TextEditingController();
  final _ufCtrl = TextEditingController();
  final _responsavelCtrl = TextEditingController();
  final _emailContatoCtrl = TextEditingController();
  final _telefoneContatoCtrl = TextEditingController();
  final _comissaoCtrl = TextEditingController();
  final _freteTaxaBaseCtrl = TextEditingController();
  final _freteValorKmCtrl = TextEditingController();
  final _freteKmMinimoCtrl = TextEditingController();
  final _freteRaioCtrl = TextEditingController();
  final _freteFatorCtrl = TextEditingController();
  final _freteTempoCtrl = TextEditingController();

  bool _ativa = true;
  bool _contribuinteIcms = false;
  bool _saving = false;
  bool _buscandoCoordenadas = false;
  String _freteModo = 'fixo';
  String _tipoLoja = 'matriz';
  String _onboardingStatus = 'ativo';
  double? _latitude;
  double? _longitude;
  final _freteService = FreteService();
  List<Map<String, dynamic>> _faixas = [];
  String? _fotoUrl;
  List<Map<String, dynamic>> _todosUsuarios = [];
  bool _loadingUsuarios = false;
  final _searchCtrl = TextEditingController();

  static const _roles = [
    'Admin',
    'Gestor',
    'Atendente',
    'Entregador',
  ];

  bool get _isEditing => widget.unidade != null;
  int? get _id => widget.unidade?['id'] as int?;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      final u = widget.unidade!;
      _nomeCtrl.text = u['nome'] ?? '';
      _enderecoCtrl.text = u['endereco'] ?? '';
      _cepCtrl.text = u['cep'] ?? '';
      _bairroCtrl.text = u['bairro'] ?? '';
      _cidadeCtrl.text = u['cidade'] ?? '';
      _fotoUrl = u['foto_url'] as String?;
      _horarioSegCtrl.text = u['horario_seg'] ?? '';
      _horarioTerCtrl.text = u['horario_ter'] ?? '';
      _horarioQuaCtrl.text = u['horario_qua'] ?? '';
      _horarioQuiCtrl.text = u['horario_qui'] ?? '';
      _horarioSexCtrl.text = u['horario_sex'] ?? '';
      _horarioSabCtrl.text = u['horario_sab'] ?? '';
      _horarioDomCtrl.text = u['horario_dom'] ?? '';
      _ordemCtrl.text = (u['ordem'] as int?)?.toString() ?? '';
      _distanciaCtrl.text = u['distancia'] ?? '';
      _cnpjCtrl.text = u['cnpj'] ?? '';
      _inscricaoEstadualCtrl.text = u['inscricao_estadual'] ?? '';
      _nomeRemetenteCtrl.text = u['nome_remetente'] ?? '';
      _numeroCtrl.text = u['numero'] ?? '';
      _complementoCtrl.text = u['complemento'] ?? '';
      _ufCtrl.text = u['uf'] ?? '';
      _responsavelCtrl.text = u['responsavel'] ?? '';
      _emailContatoCtrl.text = u['email_contato'] ?? '';
      _telefoneContatoCtrl.text = u['telefone_contato'] ?? '';
      _comissaoCtrl.text = (u['comissao_percentual'] as num?)?.toString() ?? '';
      _freteModo = u['frete_modo'] as String? ?? 'fixo';
      _tipoLoja = u['tipo_loja'] as String? ?? 'matriz';
      _onboardingStatus = u['onboarding_status'] as String? ?? 'ativo';
      _latitude = (u['latitude'] as num?)?.toDouble();
      _longitude = (u['longitude'] as num?)?.toDouble();
      _freteTaxaBaseCtrl.text =
          (u['frete_taxa_base'] as num?)?.toString() ?? '';
      _freteValorKmCtrl.text = (u['frete_valor_km'] as num?)?.toString() ?? '';
      _freteKmMinimoCtrl.text =
          (u['frete_km_minimo'] as num?)?.toString() ?? '';
      _freteRaioCtrl.text = (u['frete_raio_max_km'] as num?)?.toString() ?? '';
      _freteFatorCtrl.text = (u['frete_fator_rota'] as num?)?.toString() ?? '';
      _freteTempoCtrl.text =
          (u['frete_tempo_km_min'] as num?)?.toString() ?? '';
      final taxa = u['taxa_entrega'];
      _taxaCtrl.text = taxa == null
          ? ''
          : (taxa is num && taxa == taxa.roundToDouble()
                ? taxa.toInt().toString()
                : taxa.toString());
      final acima = u['frete_gratis_acima'];
      _freteGratisAcimaCtrl.text = acima == null
          ? ''
          : (acima is num && acima == acima.roundToDouble()
                ? acima.toInt().toString()
                : acima.toString());
      _ativa = u['ativa'] == true;
      _contribuinteIcms = u['contribuinte_icms'] == true;
    }
    if (!widget.modoParceiro) _carregarUsuarios();
    _carregarFaixas();
  }

  @override
  void dispose() {
    _nomeCtrl.dispose();
    _enderecoCtrl.dispose();
    _cepCtrl.dispose();
    _bairroCtrl.dispose();
    _cidadeCtrl.dispose();
    _horarioSegCtrl.dispose();
    _horarioTerCtrl.dispose();
    _horarioQuaCtrl.dispose();
    _horarioQuiCtrl.dispose();
    _horarioSexCtrl.dispose();
    _horarioSabCtrl.dispose();
    _horarioDomCtrl.dispose();
    _ordemCtrl.dispose();
    _distanciaCtrl.dispose();
    _taxaCtrl.dispose();
    _freteGratisAcimaCtrl.dispose();
    _cnpjCtrl.dispose();
    _inscricaoEstadualCtrl.dispose();
    _nomeRemetenteCtrl.dispose();
    _numeroCtrl.dispose();
    _complementoCtrl.dispose();
    _ufCtrl.dispose();
    _responsavelCtrl.dispose();
    _emailContatoCtrl.dispose();
    _telefoneContatoCtrl.dispose();
    _comissaoCtrl.dispose();
    _freteTaxaBaseCtrl.dispose();
    _freteValorKmCtrl.dispose();
    _freteKmMinimoCtrl.dispose();
    _freteRaioCtrl.dispose();
    _freteFatorCtrl.dispose();
    _freteTempoCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _carregarUsuarios() async {
    setState(() => _loadingUsuarios = true);
    try {
      final res = await Supabase.instance.client
          .from('perfis')
          .select('id, nome, email, funcao, unidade_id')
          .order('nome');
      setState(
        () => _todosUsuarios = (res as List).cast<Map<String, dynamic>>(),
      );
    } catch (e) {
      debugPrint('Erro ao carregar usuários: $e');
    }
    setState(() => _loadingUsuarios = false);
  }

  Future<void> _carregarFaixas() async {
    final id = _id;
    if (id == null) return;
    try {
      final res = await Supabase.instance.client
          .from('frete_faixas')
          .select()
          .eq('unidade_id', id)
          .order('km_inicio');
      if (mounted) {
        setState(() => _faixas = (res as List).cast<Map<String, dynamic>>());
      }
    } catch (e) {
      debugPrint('Erro faixas de frete: $e');
    }
  }

  Future<Map<String, dynamic>?> _dialogFaixa({
    Map<String, dynamic>? atual,
  }) async {
    final inicioCtrl = TextEditingController(
      text: (atual?['km_inicio'] as num?)?.toString() ?? '',
    );
    final fimCtrl = TextEditingController(
      text: (atual?['km_fim'] as num?)?.toString() ?? '',
    );
    final valorCtrl = TextEditingController(
      text: (atual?['valor'] as num?)?.toString() ?? '',
    );
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(atual == null ? 'Nova faixa de frete' : 'Editar faixa'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: inicioCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'KM inicial'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: fimCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'KM final'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: valorCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Valor (R\$)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              final inicio = double.tryParse(
                inicioCtrl.text.replaceAll(',', '.').trim(),
              );
              final fim = double.tryParse(
                fimCtrl.text.replaceAll(',', '.').trim(),
              );
              final valor = double.tryParse(
                valorCtrl.text.replaceAll(',', '.').trim(),
              );
              if (inicio == null ||
                  fim == null ||
                  valor == null ||
                  fim <= inicio) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(
                    content: Text('Informe km inicial, final e valor válidos.'),
                  ),
                );
                return;
              }
              Navigator.pop(ctx, {
                'km_inicio': inicio,
                'km_fim': fim,
                'valor': valor,
                'ativo': true,
              });
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    inicioCtrl.dispose();
    fimCtrl.dispose();
    valorCtrl.dispose();
    return result;
  }

  Future<void> _adicionarFaixa() async {
    final faixa = await _dialogFaixa();
    if (faixa == null) return;
    setState(() => _faixas = [..._faixas, faixa]);
  }

  Future<void> _editarFaixa(int index) async {
    final faixa = await _dialogFaixa(atual: _faixas[index]);
    if (faixa == null) return;
    setState(() {
      final novas = [..._faixas];
      novas[index] = {..._faixas[index], ...faixa};
      _faixas = novas;
    });
  }

  Future<void> _salvarFaixas(int unidadeId) async {
    try {
      await Supabase.instance.client
          .from('frete_faixas')
          .delete()
          .eq('unidade_id', unidadeId);
      if (_freteModo == 'faixas' && _faixas.isNotEmpty) {
        await Supabase.instance.client
            .from('frete_faixas')
            .insert(
              _faixas
                  .map(
                    (f) => {
                      'unidade_id': unidadeId,
                      'km_inicio': f['km_inicio'],
                      'km_fim': f['km_fim'],
                      'valor': f['valor'],
                      'ativo': true,
                    },
                  )
                  .toList(),
            );
      }
    } catch (e) {
      debugPrint('Erro ao salvar faixas: $e');
    }
  }

  String _funcaoAtual(Map<String, dynamic> user) {
    final unidadeId = user['unidade_id'];
    final funcao = user['funcao'] as String? ?? 'usuario';
    if (_id != null && unidadeId == _id && funcao != 'usuario') {
      final match = _roles.firstWhere(
        (r) => r.toLowerCase() == funcao,
        orElse: () => '',
      );
      if (match.isNotEmpty) return match;
    }
    return 'Sem vínculo';
  }

  bool _isVinculado(Map<String, dynamic> user) {
    return _funcaoAtual(user) != 'Sem vínculo';
  }

  Future<void> _atualizarFuncao(
    Map<String, dynamic> user,
    String novaFuncao,
  ) async {
    if (novaFuncao == 'Admin') {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Color(0xFFF23D4F)),
              SizedBox(width: 8),
              Text(
                'Cuidado!',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFF23D4F),
                ),
              ),
            ],
          ),
          content: Text(
            'Atribuir função Admin a "${user['nome']}" dará acesso total ao painel administrativo do app, '
            'incluindo produtos, posts, usuários e lojas.\n\nTem certeza?',
            style: const TextStyle(fontSize: 14, height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF23D4F),
                foregroundColor: Colors.white,
              ),
              child: const Text('Atribuir Admin'),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }

    try {
      if (novaFuncao == 'Sem vínculo') {
        await Supabase.instance.client
            .from('perfis')
            .update({'funcao': 'usuario', 'unidade_id': null})
            .eq('id', user['id']);
      } else {
        await Supabase.instance.client
            .from('perfis')
            .update({'funcao': novaFuncao.toLowerCase(), 'unidade_id': _id})
            .eq('id', user['id']);
      }
      await _carregarUsuarios();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao atualizar: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _pickAndUploadFoto() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );
    if (file == null) return;
    try {
      final bytes = await file.readAsBytes();
      final fileName = 'unidade_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await Supabase.instance.client.storage
          .from('Produtos')
          .uploadBinary(
            fileName,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: true,
            ),
          );
      setState(
        () => _fotoUrl = Supabase.instance.client.storage
            .from('Produtos')
            .getPublicUrl(fileName),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao fazer upload: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;
    final nome = _nomeCtrl.text.trim();
    if (nome.isEmpty) return;

    setState(() => _saving = true);

    final data = <String, dynamic>{
      'nome': nome,
      'endereco': _enderecoCtrl.text.trim(),
      'numero': _numeroCtrl.text.trim(),
      'complemento': _complementoCtrl.text.trim(),
      'cep': _cepCtrl.text.replaceAll(RegExp(r'[^0-9]'), ''),
      'bairro': _bairroCtrl.text.trim(),
      'cidade': _cidadeCtrl.text.trim(),
      'uf': _ufCtrl.text.trim().toUpperCase(),
      'inscricao_estadual': _inscricaoEstadualCtrl.text.trim(),
      'contribuinte_icms': _contribuinteIcms,
      'nome_remetente': _nomeRemetenteCtrl.text.trim(),
      'horario_seg': _horarioSegCtrl.text.trim(),
      'horario_ter': _horarioTerCtrl.text.trim(),
      'horario_qua': _horarioQuaCtrl.text.trim(),
      'horario_qui': _horarioQuiCtrl.text.trim(),
      'horario_sex': _horarioSexCtrl.text.trim(),
      'horario_sab': _horarioSabCtrl.text.trim(),
      'horario_dom': _horarioDomCtrl.text.trim(),
      'ordem': int.tryParse(_ordemCtrl.text.trim()) ?? 0,
      'ativa': _ativa,
      'distancia': _distanciaCtrl.text.trim(),
      'taxa_entrega':
          double.tryParse(_taxaCtrl.text.replaceAll(',', '.').trim()) ?? 0,
      'frete_gratis_acima': double.tryParse(
        _freteGratisAcimaCtrl.text.replaceAll(',', '.').trim(),
      ),
      'frete_modo': _freteModo,
      'frete_taxa_base':
          double.tryParse(
            _freteTaxaBaseCtrl.text.replaceAll(',', '.').trim(),
          ) ??
          0,
      'frete_valor_km':
          double.tryParse(_freteValorKmCtrl.text.replaceAll(',', '.').trim()) ??
          0,
      'frete_km_minimo':
          double.tryParse(
            _freteKmMinimoCtrl.text.replaceAll(',', '.').trim(),
          ) ??
          0,
      'frete_raio_max_km': double.tryParse(
        _freteRaioCtrl.text.replaceAll(',', '.').trim(),
      ),
      'frete_fator_rota':
          double.tryParse(_freteFatorCtrl.text.replaceAll(',', '.').trim()) ??
          1.3,
      'frete_tempo_km_min':
          double.tryParse(_freteTempoCtrl.text.replaceAll(',', '.').trim()) ??
          3,
      'tipo_loja': _tipoLoja,
      'onboarding_status': _onboardingStatus,
      if (!widget.modoParceiro)
        'comissao_percentual':
            double.tryParse(_comissaoCtrl.text.replaceAll(',', '.').trim()) ??
            0,
      'cnpj': _cnpjCtrl.text.trim(),
      'responsavel': _responsavelCtrl.text.trim(),
      'email_contato': _emailContatoCtrl.text.trim(),
      'telefone_contato': _telefoneContatoCtrl.text.trim(),
      if (_latitude != null) 'latitude': _latitude,
      if (_longitude != null) 'longitude': _longitude,
    };
    if (_fotoUrl != null) data['foto_url'] = _fotoUrl;

    try {
      int? unidadeId = _id;
      if (_isEditing) {
        await Supabase.instance.client
            .from('unidades')
            .update(data)
            .eq('id', _id!);
      } else {
        final inserida = await Supabase.instance.client
            .from('unidades')
            .insert(data)
            .select('id')
            .single();
        unidadeId = (inserida['id'] as num).toInt();
      }
      if (unidadeId != null) await _salvarFaixas(unidadeId);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1F1F1F),
      appBar: AppBar(
        title: Text(_isEditing ? 'Editar Loja Parceira' : 'Nova Loja Parceira'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _salvar,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(
                    'Salvar',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Foto
              const Text(
                'Foto da Loja',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                height: 180,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE0E0E0)),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (_fotoUrl != null && _fotoUrl!.isNotEmpty)
                      Image.network(_fotoUrl!, fit: BoxFit.cover)
                    else
                      Container(
                        color: const Color(0xFFF0F0F0),
                        child: const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.store_rounded,
                                size: 48,
                                color: Color(0xFFBBBBBB),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Nenhuma foto',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFFBBBBBB),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    Positioned(
                      bottom: 12,
                      right: 12,
                      child: ElevatedButton.icon(
                        onPressed: _pickAndUploadFoto,
                        icon: const Icon(Icons.camera_alt_rounded, size: 18),
                        label: Text(
                          _fotoUrl != null ? 'Atualizar' : 'Adicionar',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFFE50914),
                          elevation: 2,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              // Dados
              const Text(
                'Dados da Loja',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nomeCtrl,
                decoration: _inputDec('Nome', 'Ex: O Pest - Centro'),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Obrigatório' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _enderecoCtrl,
                decoration: _inputDec('Endereço', 'Ex: Rua Exemplo'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _numeroCtrl,
                      decoration: _inputDec('Número', 'Ex: 123'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _complementoCtrl,
                      decoration: _inputDec(
                        'Complemento',
                        'Ex: Sala 2 (opcional)',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _cepCtrl,
                decoration: _inputDec('CEP', '00000-000'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _bairroCtrl,
                decoration: _inputDec('Bairro', 'Ex: Centro'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      controller: _cidadeCtrl,
                      decoration: _inputDec('Cidade', 'Ex: Barreiras'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _ufCtrl,
                      maxLength: 2,
                      textCapitalization: TextCapitalization.characters,
                      decoration: _inputDec('UF', 'BA'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              // Perfil da loja parceira
              const Text(
                'Perfil da Loja Parceira',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _tipoLoja,
                decoration: _inputDec('Tipo da loja', ''),
                items: const [
                  DropdownMenuItem(value: 'matriz', child: Text('Matriz')),
                  DropdownMenuItem(value: 'parceira', child: Text('Parceira')),
                ],
                onChanged: (v) => setState(() => _tipoLoja = v ?? 'matriz'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _cnpjCtrl,
                decoration: _inputDec('CNPJ', 'CNPJ da loja (remetente)'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _inscricaoEstadualCtrl,
                decoration: _inputDec(
                  'Inscrição estadual',
                  'Somente se contribuinte do ICMS',
                ),
              ),
              const SizedBox(height: 4),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _contribuinteIcms,
                onChanged: (v) => setState(() => _contribuinteIcms = v),
                title: const Text(
                  'Contribuinte do ICMS',
                  style: TextStyle(fontSize: 13),
                ),
                subtitle: const Text(
                  'Exige chave da NF-e antes de gerar a etiqueta dos Correios.',
                  style: TextStyle(fontSize: 11),
                ),
              ),
              const SizedBox(height: 4),
              TextFormField(
                controller: _nomeRemetenteCtrl,
                decoration: _inputDec(
                  'Nome do remetente',
                  'Nome que sai na etiqueta (opcional)',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _responsavelCtrl,
                decoration: _inputDec('Responsável', 'Nome do responsável'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _emailContatoCtrl,
                      decoration: _inputDec(
                        'E-mail de contato',
                        'contato@loja.com',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _telefoneContatoCtrl,
                      decoration: _inputDec(
                        'Telefone/WhatsApp',
                        '(00) 00000-0000',
                      ),
                    ),
                  ),
                ],
              ),
              if (!widget.modoParceiro) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _comissaoCtrl,
                  decoration: _inputDec('Comissão da plataforma (%)', 'Ex: 10'),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              // Horários
              const Text(
                'Horários de Funcionamento',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              _buildHorarioField('Segunda', _horarioSegCtrl),
              _buildHorarioField('Terça', _horarioTerCtrl),
              _buildHorarioField('Quarta', _horarioQuaCtrl),
              _buildHorarioField('Quinta', _horarioQuiCtrl),
              _buildHorarioField('Sexta', _horarioSexCtrl),
              _buildHorarioField('Sábado', _horarioSabCtrl),
              _buildHorarioField('Domingo', _horarioDomCtrl),
              const SizedBox(height: 24),
              // Ordem e Distância
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _ordemCtrl,
                      decoration: _inputDec('Ordem', '0'),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _distanciaCtrl,
                      decoration: _inputDec('Distância exibida', 'Ex: 2.5 km'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              // Frete
              const Text(
                'Frete e Entrega',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              const Text(
                'A taxa é recalculada no servidor no momento do checkout.',
                style: TextStyle(fontSize: 11, color: Color(0xFF9C9C9C)),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _freteModo,
                decoration: _inputDec('Modo de frete', ''),
                items: const [
                  DropdownMenuItem(value: 'fixo', child: Text('Taxa fixa')),
                  DropdownMenuItem(
                    value: 'distancia',
                    child: Text('Por distância (km)'),
                  ),
                  DropdownMenuItem(
                    value: 'faixas',
                    child: Text('Faixas de distância'),
                  ),
                  DropdownMenuItem(
                    value: 'correios',
                    child: Text('Correios (API)'),
                  ),
                  DropdownMenuItem(
                    value: 'melhor_envio',
                    child: Text('Melhor Envio (API)'),
                  ),
                ],
                onChanged: (v) => setState(() => _freteModo = v ?? 'fixo'),
              ),
              if (_freteModo == 'correios' || _freteModo == 'melhor_envio') ...[
                const SizedBox(height: 8),
                Text(
                  _freteModo == 'correios'
                      ? 'A cotação será feita pela API dos Correios usando o CEP da loja e o CEP do cliente. Configure CORREIOS_* nas secrets das Edge Functions.'
                      : 'A cotação será feita pela API do Melhor Envio usando o CEP da loja e o CEP do cliente. Configure MELHOR_ENVIO_TOKEN nas secrets das Edge Functions.',
                  style: TextStyle(
                    fontSize: 11,
                    color: ThemeColors.secondaryText(context),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _taxaCtrl,
                      decoration: _inputDec('Taxa fixa (R\$)', 'Ex: 0'),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _freteGratisAcimaCtrl,
                      decoration: _inputDec(
                        'Frete grátis acima de (R\$)',
                        'Ex: 100 (opcional)',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                  ),
                ],
              ),
              if (_freteModo == 'distancia' || _freteModo == 'faixas') ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _freteTaxaBaseCtrl,
                        decoration: _inputDec('Taxa base (R\$)', 'Ex: 5'),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _freteValorKmCtrl,
                        decoration: _inputDec('Valor por km (R\$)', 'Ex: 1,50'),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _freteKmMinimoCtrl,
                        decoration: _inputDec('KM inclusos na base', 'Ex: 2'),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _freteRaioCtrl,
                        decoration: _inputDec(
                          'Raio máximo (km)',
                          'Ex: 15 (opcional)',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _freteFatorCtrl,
                        decoration: _inputDec('Fator de rota', 'Ex: 1.3'),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _freteTempoCtrl,
                        decoration: _inputDec('Minutos por km', 'Ex: 3'),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              if (_freteModo == 'faixas') ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Faixas de distância',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _adicionarFaixa,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Adicionar'),
                    ),
                  ],
                ),
                if (_faixas.isEmpty)
                  Text(
                    'Nenhuma faixa cadastrada. A loja usará a taxa fixa.',
                    style: TextStyle(
                      fontSize: 11,
                      color: ThemeColors.secondaryText(context),
                    ),
                  ),
                ..._faixas.asMap().entries.map(
                  (entry) => Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE0E0E0)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${(entry.value['km_inicio'] as num).toStringAsFixed(1)} km'
                            ' a ${(entry.value['km_fim'] as num).toStringAsFixed(1)} km',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        Text(
                          'R\$ ${(entry.value['valor'] as num).toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit_rounded, size: 18),
                          onPressed: () => _editarFaixa(entry.key),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            size: 18,
                          ),
                          onPressed: () => setState(() {
                            final novas = [..._faixas]..removeAt(entry.key);
                            _faixas = novas;
                          }),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _buscandoCoordenadas
                    ? null
                    : () async {
                        setState(() => _buscandoCoordenadas = true);
                        final coordenadas = await _freteService.geocodificar(
                          cep: _cepCtrl.text,
                          rua: _enderecoCtrl.text,
                          bairro: _bairroCtrl.text,
                          cidade: _cidadeCtrl.text,
                        );
                        if (coordenadas != null) {
                          setState(() {
                            _latitude = coordenadas.latitude;
                            _longitude = coordenadas.longitude;
                          });
                        }
                        setState(() => _buscandoCoordenadas = false);
                        if (coordenadas == null && mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Não foi possível localizar o endereço da loja.',
                              ),
                              backgroundColor: AppColors.error,
                            ),
                          );
                        }
                      },
                icon: _buscandoCoordenadas
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.my_location_rounded, size: 18),
                label: Text(
                  _latitude != null && _longitude != null
                      ? 'Origem confirmada: ${_latitude!.toStringAsFixed(5)}, ${_longitude!.toStringAsFixed(5)}'
                      : 'Localizar origem no mapa',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              if (_latitude != null && _longitude != null) ...[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    height: 150,
                    child: FlutterMap(
                      options: MapOptions(
                        initialCenter: LatLng(_latitude!, _longitude!),
                        initialZoom: 15,
                        interactionOptions: const InteractionOptions(
                          flags:
                              InteractiveFlag.drag |
                              InteractiveFlag.pinchZoom |
                              InteractiveFlag.doubleTapZoom,
                        ),
                      ),
                      children: [
                        TileLayer(
                          urlTemplate:
                              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.opest.shop',
                        ),
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: LatLng(_latitude!, _longitude!),
                              width: 40,
                              height: 40,
                              child: const Icon(
                                Icons.location_on_rounded,
                                color: Color(0xFFE50914),
                                size: 40,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              SwitchListTile(
                title: const Text('Loja Ativa'),
                value: _ativa,
                onChanged: (v) => setState(() => _ativa = v),
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 32),
              if (_isEditing && !widget.modoParceiro)
                _buildFuncionariosSection(),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDec(String label, String hint) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    );
  }

  Widget _buildHorarioField(String label, TextEditingController ctrl) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextFormField(
        controller: ctrl,
        decoration: _inputDec(label, 'Ex: 08:00-18:00'),
      ),
    );
  }

  Widget _buildFuncionariosSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Funcionários',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        const Text(
          'Atribua funções aos usuários cadastrados.',
          style: TextStyle(fontSize: 12, color: Color(0xFF9C9C9C)),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _searchCtrl,
          decoration: InputDecoration(
            hintText: 'Buscar por nome ou email...',
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(
              vertical: 0,
              horizontal: 12,
            ),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        if (_loadingUsuarios)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ),
          )
        else
          _buildUsuariosList(),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildUsuariosList() {
    final query = _searchCtrl.text.toLowerCase().trim();
    final filtrados = _todosUsuarios.where((u) {
      if (query.isEmpty) return true;
      final nome = (u['nome'] as String? ?? '').toLowerCase();
      final email = (u['email'] as String? ?? '').toLowerCase();
      return nome.contains(query) || email.contains(query);
    }).toList();

    if (filtrados.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE0E0E0)),
        ),
        child: const Center(
          child: Text(
            'Nenhum usuário encontrado',
            style: TextStyle(color: Color(0xFF9C9C9C)),
          ),
        ),
      );
    }

    return Column(
      children: filtrados.map((user) {
        final nome = user['nome'] as String? ?? '';
        final email = user['email'] as String? ?? '';
        final funcaoAtual = _funcaoAtual(user);
        final isVinculado = funcaoAtual != 'Sem vínculo';
        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isVinculado
                  ? const Color(0xFFE50914).withValues(alpha: 0.3)
                  : const Color(0xFF2C2C2C),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: isVinculado
                      ? const Color(0xFFE50914).withValues(alpha: 0.12)
                      : const Color(0xFFF0F0F0),
                  child: Text(
                    nome.isNotEmpty ? nome[0].toUpperCase() : '?',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isVinculado
                          ? const Color(0xFFE50914)
                          : const Color(0xFF9C9C9C),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nome,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        email,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF9C9C9C),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  constraints: const BoxConstraints(minWidth: 130),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: DropdownButtonFormField<String>(
                    value: funcaoAtual,
                    isDense: true,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: isVinculado
                          ? const Color(0xFFE50914).withValues(alpha: 0.06)
                          : const Color(0xFF1F1F1F),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                    ),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isVinculado
                          ? const Color(0xFFE50914)
                          : const Color(0xFF9C9C9C),
                    ),
                    iconSize: 18,
                    items: [
                      const DropdownMenuItem(
                        value: 'Sem vínculo',
                        child: Text(
                          'Sem vínculo',
                          style: TextStyle(fontSize: 11),
                        ),
                      ),
                      ..._roles.map(
                        (r) => DropdownMenuItem(
                          value: r,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (r == 'Admin') ...[
                                const Icon(
                                  Icons.warning_amber_rounded,
                                  size: 13,
                                  color: Color(0xFFF23D4F),
                                ),
                                const SizedBox(width: 4),
                              ],
                              Text(
                                r,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: r == 'Admin'
                                      ? const Color(0xFFF23D4F)
                                      : null,
                                  fontWeight: r == 'Admin'
                                      ? FontWeight.w700
                                      : FontWeight.normal,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    onChanged: (v) {
                      if (v != null && v != funcaoAtual)
                        _atualizarFuncao(user, v);
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
