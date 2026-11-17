import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:o_pest_shop/ui/widgets/app_states.dart';
import 'package:o_pest_shop/ui/widgets/banner_carousel.dart';

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

  testWidgets('BannerCarousel oculta quando vazio e exibe estático com 1 item',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: BannerCarousel(banners: [])),
    ));
    expect(find.byType(PageView), findsNothing);

    Map<String, dynamic>? clicado;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BannerCarousel(
          banners: const [
            {
              'id': 1,
              'titulo': 'Super Whey',
              'imagem_url': '',
              'link_url': '/busca',
            },
          ],
          onTap: (b) => clicado = b,
        ),
      ),
    ));
    await tester.pump();

    expect(find.text('Super Whey'), findsOneWidget);
    expect(find.text('DESTAQUE'), findsOneWidget);
    expect(find.text('Ver oferta →'), findsOneWidget);
    expect(find.byType(AnimatedContainer), findsNothing);

    await tester.tap(find.text('Super Whey'));
    expect(clicado?['id'], 1);
  });

  testWidgets('BannerCarousel com múltiplos banners faz loop e autoplay',
      (tester) async {
    final banners = [
      {'id': 1, 'titulo': 'Banner Um', 'imagem_url': '', 'link_url': '/a'},
      {'id': 2, 'titulo': 'Banner Dois', 'imagem_url': '', 'link_url': ''},
    ];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BannerCarousel(
          banners: banners,
          interval: const Duration(seconds: 2),
        ),
      ),
    ));
    await tester.pump();

    expect(find.text('Banner Um'), findsWidgets);
    expect(find.byType(AnimatedContainer), findsNWidgets(2));

    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.text('Banner Dois'), findsWidgets);
  });
}
