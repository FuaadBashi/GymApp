"""Split a JEFIT multi-section CSV export into named tables.

Some sections repeat the header before every row (ROUTINES), so blocks with an
identical header are merged into one table, keeping file order.
"""
import csv, io, re, sys

def parse(path):
    text = open(path, encoding="utf-8", newline="").read()
    sections = {}
    parts = re.split(r"^### ([A-Z ]+?) #+\s*$", text, flags=re.M)
    for i in range(1, len(parts), 2):
        name = parts[i].strip()
        body = parts[i + 1].split("\n######################################################")[0]
        rows = list(csv.reader(io.StringIO(body.strip("\n"))))
        tables = {}  # header tuple -> rows
        order = []   # (table_key, row) in file order
        header = None
        for r in rows:
            if not r or all(c == "" for c in r):
                header = None
                continue
            if header is None:
                header = tuple(r)
                tables.setdefault(header, [])
                continue
            d = dict(zip(header, r))
            tables[header].append(d)
            order.append((header, d))
        sections[name] = {"tables": tables, "order": order}
    return sections

def table(sections, name, must_have):
    for h, rows in sections[name]["tables"].items():
        if must_have in h:
            return rows
    return []

if __name__ == "__main__":
    s = parse(sys.argv[1])
    for name, v in s.items():
        for h, rows in v["tables"].items():
            print(f"{name}: {len(rows)} rows | {','.join(h)[:160]}")
