import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_colors.dart';

class UnidadeFormScreen extends StatefulWidget {
  final Map<String, dynamic>? unidade;
  const UnidadeFormScreen({super.key, this.unidade});

  @override
  State<UnidadeFormScreen> createState() => _UnidadeFormScreenState();
}

class _UnidadeFormScreenState extends State<UnidadeFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nomeCtrl = TextEditingController();
  final _enderecoCtrl = TextEditingController();
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

  bool _ativa = true;
  bool _saving = false;
  String? _fotoUrl;
  List<Map<String, dynamic>> _todosUsuarios = [];
  bool _loadingUsuarios = false;
  final _searchCtrl = TextEditingController();

  static const _roles = ['Admin', 'Gestor', 'Atendente', 'Personal', 'Nutricionista'];

  bool get _isEditing => widget.unidade != null;
  int? get _id => widget.unidade?['id'] as int?;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      final u = widget.unidade!;
      _nomeCtrl.text = u['nome'] ?? '';
      _enderecoCtrl.text = u['endereco'] ?? '';
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
      _ativa = u['ativa'] == true;
    }
    _carregarUsuarios();
  }

  @override
  void dispose() {
    _nomeCtrl.dispose();
    _enderecoCtrl.dispose();
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
      setState(() => _todosUsuarios = (res as List).cast<Map<String, dynamic>>());
    } catch (e) {
      debugPrint('Erro ao carregar usuários: $e');
    }
    setState(() => _loadingUsuarios = false);
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

  Future<void> _atualizarFuncao(Map<String, dynamic> user, String novaFuncao) async {
    if (novaFuncao == 'Admin') {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Color(0xFFF23D4F)),
              SizedBox(width: 8),
              Text('Cuidado!', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFFF23D4F))),
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
          SnackBar(content: Text('Erro ao atualizar: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _pickAndUploadFoto() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (file == null) return;
    try {
      final bytes = await file.readAsBytes();
      final fileName = 'unidade_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await Supabase.instance.client.storage.from('Produtos').uploadBinary(
        fileName, bytes,
        fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
      );
      setState(() => _fotoUrl = Supabase.instance.client.storage.from('Produtos').getPublicUrl(fileName));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao fazer upload: $e'), backgroundColor: AppColors.error),
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
      'bairro': _bairroCtrl.text.trim(),
      'cidade': _cidadeCtrl.text.trim(),
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
    };
    if (_fotoUrl != null) data['foto_url'] = _fotoUrl;

    try {
      if (_isEditing) {
        await Supabase.instance.client.from('unidades').update(data).eq('id', _id!);
      } else {
        await Supabase.instance.client.from('unidades').insert(data);
      }
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
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Salvar', style: TextStyle(fontWeight: FontWeight.w600)),
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
              const Text('Foto da Loja', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
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
                              Icon(Icons.store_rounded, size: 48, color: Color(0xFFBBBBBB)),
                              SizedBox(height: 4),
                              Text('Nenhuma foto', style: TextStyle(fontSize: 12, color: Color(0xFFBBBBBB))),
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
                        label: Text(_fotoUrl != null ? 'Atualizar' : 'Adicionar'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFFE50914),
                          elevation: 2,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              // Dados
              const Text('Dados da Loja', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nomeCtrl,
                decoration: _inputDec('Nome', 'Ex: O Pest - Centro'),
                validator: (v) => v == null || v.trim().isEmpty ? 'Obrigatório' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(controller: _enderecoCtrl, decoration: _inputDec('Endereço', 'Ex: Rua Exemplo, 123')),
              const SizedBox(height: 12),
              TextFormField(controller: _bairroCtrl, decoration: _inputDec('Bairro', 'Ex: Centro')),
              const SizedBox(height: 12),
              TextFormField(controller: _cidadeCtrl, decoration: _inputDec('Cidade', 'Ex: Barreiras - BA')),
              const SizedBox(height: 24),
              // Horários
              const Text('Horários de Funcionamento', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
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
                    child: TextFormField(controller: _ordemCtrl, decoration: _inputDec('Ordem', '0'), keyboardType: TextInputType.number),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(controller: _distanciaCtrl, decoration: _inputDec('Distância', 'Ex: 2.5 km')),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                title: const Text('Loja Ativa'),
                value: _ativa,
                onChanged: (v) => setState(() => _ativa = v),
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 32),
              if (_isEditing) _buildFuncionariosSection(),
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
        const Text('Funcionários', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        const Text('Atribua funções aos usuários cadastrados.',
            style: TextStyle(fontSize: 12, color: Color(0xFF9C9C9C))),
        const SizedBox(height: 12),
        TextField(
          controller: _searchCtrl,
          decoration: InputDecoration(
            hintText: 'Buscar por nome ou email...',
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        if (_loadingUsuarios)
          const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
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
          child: Text('Nenhum usuário encontrado', style: TextStyle(color: Color(0xFF9C9C9C))),
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
              color: isVinculado ? const Color(0xFFE50914).withValues(alpha: 0.3) : const Color(0xFF2C2C2C),
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
                      color: isVinculado ? const Color(0xFFE50914) : const Color(0xFF9C9C9C),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(nome, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      Text(email, style: const TextStyle(fontSize: 11, color: Color(0xFF9C9C9C))),
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
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    ),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isVinculado ? const Color(0xFFE50914) : const Color(0xFF9C9C9C),
                    ),
                    iconSize: 18,
                    items: [
                      const DropdownMenuItem(
                        value: 'Sem vínculo',
                        child: Text('Sem vínculo', style: TextStyle(fontSize: 11)),
                      ),
                      ..._roles.map((r) => DropdownMenuItem(
                        value: r,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (r == 'Admin') ...[
                              const Icon(Icons.warning_amber_rounded, size: 13, color: Color(0xFFF23D4F)),
                              const SizedBox(width: 4),
                            ],
                            Text(r, style: TextStyle(
                              fontSize: 11,
                              color: r == 'Admin' ? const Color(0xFFF23D4F) : null,
                              fontWeight: r == 'Admin' ? FontWeight.w700 : FontWeight.normal,
                            )),
                          ],
                        ),
                      )),
                    ],
                    onChanged: (v) {
                      if (v != null && v != funcaoAtual) _atualizarFuncao(user, v);
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
