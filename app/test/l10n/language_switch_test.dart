// DshApp reacts to the retained language owner; no retired settings route fixture.
import 'package:dsh_app/app.dart';
import 'package:dsh_app/l10n/l10n.dart';
import 'package:dsh_app/state/locale_state.dart';
import 'package:dsh_app/state/settings_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../support/lite_harness.dart' show FakeSettings;
class _Plain extends StatelessWidget {const _Plain();@override Widget build(BuildContext context)=>Text('plain ${appL10n.commonCancel}');}
class _Page extends StatelessWidget {
 const _Page();@override Widget build(BuildContext context)=>Scaffold(body:Column(children:[Text('ctx ${context.l10n.commonCancel}'),const _Plain()]));
}
void main(){
 tearDown((){AppLanguageController.initial=AppLanguage.zh;AppLocale.use(AppLocale.zhCN);});
 Future<ProviderContainer> pump(WidgetTester tester) async{
  final c=ProviderContainer(overrides:[settingsProvider.overrideWith(()=>FakeSettings(const AppSettings(loaded:true)))]);addTearDown(c.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(container:c,child:const DshApp(home:_Page())));await tester.pumpAndSettle();return c;
 }
 testWidgets('language change rebuilds context and plain readers and persists for native notifications',(tester) async{
  SharedPreferences.setMockInitialValues({});final c=await pump(tester);
  expect(find.text('ctx 取消'),findsOneWidget);expect(find.text('plain 取消'),findsOneWidget);
  await c.read(appLanguageProvider.notifier).set(AppLanguage.en);await tester.pumpAndSettle();
  expect(find.text('ctx Cancel'),findsOneWidget);expect(find.text('plain Cancel'),findsOneWidget);
  expect(AppLocale.current,AppLocale.en);expect(Localizations.localeOf(tester.element(find.byType(_Page))),AppLocale.en);
  expect((await SharedPreferences.getInstance()).getString(AppLanguageController.prefsKey),'en');
  await c.read(appLanguageProvider.notifier).set(AppLanguage.zh);await tester.pumpAndSettle();expect(find.text('plain 取消'),findsOneWidget);
 });
 testWidgets('stored language is available on first frame',(tester) async{
  SharedPreferences.setMockInitialValues({AppLanguageController.prefsKey:'en'});await AppLanguageController.load();
  expect(AppLanguageController.initial,AppLanguage.en);await pump(tester);expect(find.text('ctx Cancel'),findsOneWidget);
 });
}
