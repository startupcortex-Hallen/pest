import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/helpers/scale_helper.dart';
import '../../../core/helpers/theme_colors.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../widgets/app_top_bar.dart';
import '../../widgets/custom_drawer.dart';
import '../../widgets/unit_card.dart';
import '../../widgets/animated_card_entry.dart';

class UnidadesScreen extends StatefulWidget {
  const UnidadesScreen({super.key});

  @override
  State<UnidadesScreen> createState() => _UnidadesScreenState();
}

class _UnidadesScreenState extends State<UnidadesScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  List<Map<String, dynamic>> _unidades = [];
  List<Map<String, dynamic>> _filtradas = [];
  bool _loading = true;
  String? _erroMensagem;
  String? _cidadeSelecionada;
  final _searchCtrl = TextEditingController();

  List<String> get _cidades => _unidades
      .map((u) => u['cidade'] as String? ?? '')
      .where((c) => c.isNotEmpty)
      .toSet()
      .toList()
    ..sort();

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    setState(() {
      _loading = true;
      _erroMensagem = null;
    });
    try {
      print('██ UNIDADES: _carregar() iniciou');
      final response = await Supabase.instance.client
          .from('unidades')
          .select()
          .eq('ativa', true)
          .order('ordem', ascending: true);
      print('██ UNIDADES: resposta tipo=${response.runtimeType}');
      if (response is List) {
        _unidades = response.cast<Map<String, dynamic>>();
        print('██ UNIDADES: ${_unidades.length} registros');
      } else {
        _unidades = [];
        _erroMensagem = 'Resposta inesperada: ${response.runtimeType}';
      }
    } catch (e, stack) {
      _unidades = [];
      _erroMensagem = 'Erro: $e';
      print('██ UNIDADES: ERRO=$e');
      print('██ UNIDADES: STACK=$stack');
    }
    _aplicarFiltro();
    print('██ UNIDADES: _filtradas=${_filtradas.length} _erro=$_erroMensagem');
    if (mounted) setState(() => _loading = false);
  }

  Map<String, dynamic> _extrairHorarios(Map<String, dynamic> u) {
    final horarios = <String, dynamic>{};
    for (final dia in ['seg', 'ter', 'qua', 'qui', 'sex', 'sab', 'dom']) {
      final chave = 'horario_$dia';
      if (u[chave] != null) horarios[dia] = u[chave];
    }
    return horarios;
  }

  void _aplicarFiltro() {
    _filtradas = _unidades.where((u) {
      if (_cidadeSelecionada != null && u['cidade'] != _cidadeSelecionada) return false;
      if (_searchCtrl.text.isNotEmpty) {
        final q = _searchCtrl.text.toLowerCase();
        final nome = (u['nome'] as String? ?? '').toLowerCase();
        final bairro = (u['bairro'] as String? ?? '').toLowerCase();
        final cidade = (u['cidade'] as String? ?? '').toLowerCase();
        if (!nome.contains(q) && !bairro.contains(q) && !cidade.contains(q)) return false;
      }
      return true;
    }).toList();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: ThemeColors.background(context),
      drawer: const CustomDrawer(),
      body: Column(
        children: [
          AppTopBar.withTitle(
            onMenuTap: () => _scaffoldKey.currentState?.openDrawer(),
            title: 'Lojas Parceiras',
            subtitle: 'Encontre a loja parceira mais próxima',
            bottomWidget: _buildFilters(context),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
                context.w(AppSpacing.md), context.h(AppSpacing.md), context.w(AppSpacing.md), 0),
            child: Row(
              children: [
                Icon(Icons.store_mall_directory_rounded, color: ThemeColors.primary(context), size: context.sp(22)),
                SizedBox(width: context.w(AppSpacing.sm)),
                Text('Lojas Parceiras',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                const Spacer(),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: context.w(AppSpacing.sm), vertical: context.h(4)),
                  decoration: BoxDecoration(
                    color: ThemeColors.primary(context).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppRadius.rLg(context)),
                  ),
                  child: Text('${_filtradas.length}',
                      style: TextStyle(fontSize: context.sp(12), color: ThemeColors.primary(context), fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
          Expanded(
            child: _buildBody(),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          context.w(AppSpacing.md), 0, context.w(AppSpacing.md), context.h(AppSpacing.md)),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Container(
              height: context.h(40).clamp(32.0, 44.0),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(AppRadius.rLg(context)),
              ),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (_) => _aplicarFiltro(),
                style: const TextStyle(color: Color(0xFFEDEDED), fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Bairro, cidade ou CEP...',
                  hintStyle: const TextStyle(color: Color(0xFF9C9C9C), fontSize: 14),
                  prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF9C9C9C), size: 20),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: context.h(10)),
                ),
              ),
            ),
          ),
          SizedBox(width: context.w(AppSpacing.sm)),
          Container(
            height: context.h(40).clamp(32.0, 44.0),
            padding: EdgeInsets.symmetric(horizontal: context.w(AppSpacing.sm)),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(AppRadius.rLg(context)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _cidadeSelecionada,
                hint: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.location_city_rounded, color: const Color(0xFFC6C6C6), size: context.sp(16)),
                    SizedBox(width: context.w(4)),
                    const Text('Filtrar', style: TextStyle(color: Color(0xFFC6C6C6), fontSize: 13)),
                  ],
                ),
                icon: Icon(Icons.keyboard_arrow_down_rounded, color: const Color(0xFFC6C6C6), size: context.sp(18)),
                isDense: true,
                dropdownColor: Colors.white,
                items: [
                  DropdownMenuItem(
                    value: null,
                    child: const Text('Todas as cidades', style: TextStyle(fontSize: 13)),
                  ),
                  ..._cidades.map((c) => DropdownMenuItem(
                    value: c,
                    child: Text(c, style: const TextStyle(fontSize: 13)),
                  )),
                ],
                onChanged: (v) {
                  setState(() => _cidadeSelecionada = v);
                  _aplicarFiltro();
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_erroMensagem != null) {
      return Center(child: Text(_erroMensagem!, style: TextStyle(color: ThemeColors.error(context))));
    }

    if (_unidades.isEmpty) {
      return Center(child: Text('Nenhuma unidade cadastrada', style: TextStyle(color: ThemeColors.secondaryText(context))));
    }

    if (_filtradas.isEmpty) {
      return Center(child: Text('Nenhuma unidade encontrada', style: TextStyle(color: ThemeColors.secondaryText(context))));
    }

    return ListView.builder(
      padding: EdgeInsets.fromLTRB(
          context.w(AppSpacing.md), context.h(AppSpacing.md), context.w(AppSpacing.md), context.h(120)),
      itemCount: _filtradas.length,
      itemBuilder: (context, index) {
        final u = _filtradas[index];
        return Padding(
          padding: EdgeInsets.only(bottom: context.h(AppSpacing.md)),
          child: UnitCard(
            nome: u['nome'] as String? ?? '',
            bairro: u['bairro'] as String?,
            endereco: u['endereco'] as String?,
            distancia: u['distancia'] as String?,
            fotoUrl: u['foto_url'] as String?,
            horarios: _extrairHorarios(u),
            onTap: () => context.push('/unidade/${u['id']}'),
          ),
        );
      },
    );
  }
}
