import 'package:flutter/material.dart';
import 'aviso_detail_screen.dart';
import 'evento_detail_screen.dart';
import 'novidade_detail_screen.dart';
import 'post_detail_screen.dart';
import 'vaga_detail_screen.dart';

void pushPostDetail(BuildContext context, String postId, String categoria) {
  final Widget screen;
  final cat = categoria.toLowerCase();
  if (cat.startsWith('aviso')) {
    screen = AvisoDetailScreen(postId: postId);
  } else if (cat.startsWith('novidade')) {
    screen = NovidadeDetailScreen(postId: postId);
  } else if (cat.startsWith('evento')) {
    screen = EventoDetailScreen(postId: postId);
  } else if (cat.startsWith('vaga')) {
    screen = VagaDetailScreen(postId: postId);
  } else {
    screen = PostDetailScreen(postId: postId);
  }

  Navigator.of(context).push<dynamic>(
    PageRouteBuilder<dynamic>(
      pageBuilder: (_, __, ___) => screen,
      transitionsBuilder: (_, Animation<double> animation, __, Widget child) {
        return FadeTransition(opacity: animation, child: child);
      },
      transitionDuration: const Duration(milliseconds: 700),
      reverseTransitionDuration: const Duration(milliseconds: 500),
    ),
  );
}
