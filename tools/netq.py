#!/usr/bin/env python3
"""Query a KiCad XML netlist of the Ocean-240.2 replica.

Make the netlist first:
  kicad-cli sch export netlist --format kicadxml -o /tmp/ocean.xml upstream/ocean-240.2/KiCAD/Океан-240.2.kicad_sch

  netq.py NETLIST part DD42        pins of a part: pin, pin name, net, other ends of the net
  netq.py NETLIST net CPU_F1       all pins on nets whose name contains the text
  netq.py NETLIST parts            ref, value, sheet of every part
"""
import sys
import xml.etree.ElementTree as ET


def load(path):
    root = ET.parse(path).getroot()
    parts = {}
    for c in root.iter('comp'):
        ref = c.get('ref')
        sheet = c.find('sheetpath')
        parts[ref] = (c.findtext('value'), sheet.get('names') if sheet is not None else '')
    pinnames = {}
    for lp in root.iter('libpart'):
        key = (lp.get('lib'), lp.get('part'))
        pinnames[key] = {p.get('num'): p.get('name') for p in lp.iter('pin')}
    nets = {}
    for n in root.iter('net'):
        nets[n.get('name')] = [(nd.get('ref'), nd.get('pin'), nd.get('pinfunction') or '') for nd in n.iter('node')]
    return parts, nets


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)
    parts, nets = load(sys.argv[1])
    cmd = sys.argv[2]
    if cmd == 'parts':
        for r in sorted(parts, key=lambda s: (s.rstrip('0123456789.'), len(s), s)):
            print(f'{r:8} {parts[r][0]:20} {parts[r][1]}')
    elif cmd == 'part':
        ref = sys.argv[3]
        print(ref, parts.get(ref))
        rows = []
        for name, nodes in nets.items():
            for r, pin, fn in nodes:
                if r == ref:
                    others = ' '.join(f'{r2}.{p2}' + (f'({f2})' if f2 else '') for r2, p2, f2 in nodes if r2 != ref)
                    rows.append((int(pin) if pin.isdigit() else 999, pin, fn, name, others))
        for _, pin, fn, name, others in sorted(rows):
            print(f'  {pin:>3} {fn:10} {name:30} {others[:160]}')
    elif cmd == 'net':
        text = sys.argv[3]
        for name, nodes in sorted(nets.items()):
            if text in name:
                print(name, ' '.join(f'{r}.{p}' + (f'({f})' if f else '') for r, p, f in nodes))
    else:
        print(__doc__)
        sys.exit(1)


if __name__ == '__main__':
    main()
