import 'package:flutter_test/flutter_test.dart';
import 'package:farsha/cloud_models.dart';
void main(){
 group('multi branch models',(){
  test('inventory keeps branch snapshot and linear meters',(){final x=InventoryRecord.fromMap({'id':'i','name':'دهب','color':'رمادي','remaining_length':43,'wholesale_price':25,'low_stock_at':10,'branch_id':'b','branches':{'name':'الملقا'}});expect(x.remainingLength,43);expect(x.branchName,'الملقا');expect(x.isLow,false);});
  test('branch record supports default branch',(){final b=BranchRecord.fromMap({'id':'b','name':'الرئيسي','code':'MAIN','city':'الرياض','address':'','phone':'','status':'active','is_default':true});expect(b.isDefault,true);expect(b.status,'active');});
  test('partner is independent from employee role',(){final p=PartnerRecord.fromMap({'id':'p','display_name':'أحمد','relationship_type':'administrative_partner','status':'active','user_id':null});expect(p.relationship,'administrative_partner');expect(p.userId,isNull);});
 });
}