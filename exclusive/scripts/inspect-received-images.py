from pathlib import Path
from PIL import Image,ImageDraw
import json,base64,hashlib
root=Path('recebidos/2026-09-18')
old={hashlib.sha256(p.read_bytes()).hexdigest():str(p) for p in Path('assets').rglob('*') if p.is_file()}
for group in ['sala','cozinha']:
 files=sorted(p for p in (root/group).rglob('*') if p.suffix.lower() in ['.png','.jpg'])
 assets=[]; info=[]; thumbs=[]
 for i,p in enumerate(files):
  data=p.read_bytes(); im=Image.open(p); aid=f'{group}-{i}'
  assets.append(dict(id=aid,name=p.name,width=im.width,height=im.height,data='data:image/'+('png' if p.suffix=='.png' else 'jpeg')+';base64,'+base64.b64encode(data).decode()))
  info.append(dict(name=p.name,size=list(im.size),mode=im.mode,identical_to=old.get(hashlib.sha256(data).hexdigest())))
  tile=Image.new('RGB',(420,220),'#ddd9d1'); im.thumbnail((410,175)); tile.paste(im,(5,38),im if im.mode=='RGBA' else None); ImageDraw.Draw(tile).text((5,5),f'{i}: {p.name}',fill='black'); thumbs.append(tile)
 base=next(a for a in assets if 'base sala' in a['name'].lower() or a['name'].startswith('0 -'))
 combos=[]
 for a in assets:
  selected=[base['id'],a['id']] if a['name'].endswith('.png') else [a['id']]
  combos.append(dict(id='review-'+a['id'],name=a['name'],environment=group.capitalize(),unit='',typology='',view='perspective',notes='Arquivo recebido em 18/09. Composição para conferência; associação às opções ainda não validada.',layers=[dict(assetId=b['id'],visible=b['id'] in selected) for b in assets]))
 project=dict(format='exclusive-image-review',version=1,name=group.upper()+' — recebidos 18-09-2026',assets=assets,combinations=combos)
 (root/(group+'-revisao.json')).write_text(json.dumps(project,ensure_ascii=False),encoding='utf8')
 (root/(group+'-inventario.json')).write_text(json.dumps(info,ensure_ascii=False,indent=2),encoding='utf8')
 sheet=Image.new('RGB',(1260,220*((len(thumbs)+2)//3)),'white')
 for i,t in enumerate(thumbs):sheet.paste(t,((i%3)*420,(i//3)*220))
 sheet.save(root/(group+'-contato.jpg'))
 print(group,len(files),'imagens;',sum(bool(x['identical_to']) for x in info),'idênticas às existentes; tamanhos:',sorted(set(tuple(x['size']) for x in info)))
