import 'package:prosapia/src/page_format.dart';
import 'package:prosapia/src/render.dart';
import 'package:prosapia/src/tree.dart';
import 'package:test/test.dart';

void main() {
  test('the guide\'s example page reads cleanly, in its normal form', () {
    final p = Person.fromSource('p-0', 'x-0', Renderer.examplePage);
    expect(p.issues, isEmpty);
    expect(p.children.map((c) => c.qualifier), [null, 'adopted']);
    expect(p.couples.single.event.sources, ['Pennsylvania marriage records']);
    expect(formatPage(Renderer.examplePage), Renderer.examplePage);
  });
}
