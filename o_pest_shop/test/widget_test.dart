import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:o_pest_shop/ui/widgets/app_states.dart';

void main() {
  testWidgets('AppEmptyState mostra título, mensagem e dispara ação',
      (tester) async {
    var acionado = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AppEmptyState(
          icon: Icons.shopping_cart_outlined,
          title: 'Carrinho vazio',
          message: 'Adicione produtos',
          actionLabel: 'Continuar',
          onAction: () => acionado = true,
        ),
      ),
    ));

    expect(find.text('Carrinho vazio'), findsOneWidget);
    expect(find.text('Adicione produtos'), findsOneWidget);

    await tester.tap(find.text('Continuar'));
    expect(acionado, isTrue);
  });

  testWidgets('AppErrorState dispara retry', (tester) async {
    var tentou = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AppErrorState(message: 'Falhou', onRetry: () => tentou = true),
      ),
    ));

    expect(find.text('Falhou'), findsOneWidget);
    await tester.tap(find.text('Tentar novamente'));
    expect(tentou, isTrue);
  });

  testWidgets('AppSkeleton renderiza e anima sem erro', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: AppSkeleton(height: 20)),
    ));
    expect(find.byType(AppSkeleton), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 450));
    expect(find.byType(AppSkeleton), findsOneWidget);
  });
}
