import render_native_reference as n
class Gun(n.NativeRenderer):
 def render_symbol(self,name,frame,where,ct=n.base.CT_IDENTITY):
  if name=="无AS链接/Symbol 3838": frame=2
  return super().render_symbol(name,frame,where,ct=ct)
 def element_to_svg(self,el,where,ct=n.base.CT_IDENTITY):
  if el.get('name')=='枪口位置':
   self.removed.append({'where':where,'instance':'枪口位置','reason':'nonvisual muzzle registration marker'});return ''
  return super().element_to_svg(el,where,ct)
n.NativeRenderer=Gun
if __name__=='__main__':n.main()
