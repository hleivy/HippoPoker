import sys

path = sys.argv[1] if len(sys.argv) > 1 else 'lib/pages/table_page.dart'
src = open(path, encoding='utf-8').read()
i = 0
n = len(src)
stack = []
pairs = {')': '(', ']': '[', '}': '{'}
line = 1
in_line_comment = False
in_block_comment = False
in_str = None
triple = None
while i < n:
    c = src[i]
    if c == '\n':
        line += 1
        in_line_comment = False
        i += 1
        continue
    if in_line_comment:
        i += 1
        continue
    if in_block_comment:
        if c == '*' and i + 1 < n and src[i + 1] == '/':
            in_block_comment = False
            i += 2
            continue
        i += 1
        continue
    if in_str:
        if c == '\\':
            i += 2
            continue
        if triple:
            if c == in_str and i + 2 < n and src[i + 1] == in_str and src[i + 2] == in_str:
                in_str = None
                triple = None
                i += 3
                continue
            i += 1
            continue
        else:
            if c == in_str:
                in_str = None
                i += 1
                continue
            i += 1
            continue
    # not in string/comment
    if c == '/' and i + 1 < n and src[i + 1] == '/':
        in_line_comment = True
        i += 2
        continue
    if c == '/' and i + 1 < n and src[i + 1] == '*':
        in_block_comment = True
        i += 2
        continue
    if c == "'":
        if src[i:i + 3] == "'''":
            triple = "'"
            in_str = "'"
            i += 3
            continue
        in_str = "'"
        i += 1
        continue
    if c == '"':
        if src[i:i + 3] == '"""':
            triple = '"'
            in_str = '"'
            i += 3
            continue
        in_str = '"'
        i += 1
        continue
    if c in '([{':
        stack.append((c, line))
        i += 1
        continue
    if c in ')]}':
        if not stack:
            print('UNMATCHED CLOSING', c, 'at line', line)
            i += 1
            continue
        o, lo = stack.pop()
        if pairs[c] != o:
            print('MISMATCH: opened', o, 'line', lo, 'closed', c, 'line', line)
            i += 1
            continue
        i += 1
        continue
    i += 1
if stack:
    print('UNCLOSED:', stack)
else:
    print('BRACKETS BALANCED')
