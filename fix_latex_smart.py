#!/usr/bin/env python3
r"""
Convertit les équations LaTeX brutes en syntaxe pandoc $...$ et $$...$$
+ Supprime les images distantes
+ Corrige les virgules dans les intégrales: ,dt -> \,dt
+ Corrige ;\sim; ;\circ; -> \sim \circ
+ Supprime les lignes de séparation (===, ---) qui sont seules sur leur ligne
+ Échappe les # en \# dans les blocs mathématiques (pour pandoc)
+ Chaque $$ est sur sa propre ligne
"""

import re
import sys
from pathlib import Path

LATEX_COMMANDS = re.compile(
    r'\\(?:frac|int|sum|prod|sqrt|partial|infty|pm|mp|times|div|cdot|circ|sim|'
    r'approx|equiv|leq|geq|neq|rightarrow|leftarrow|leftrightarrow|boxed|mid|'
    r'Rightarrow|Leftarrow|to|mapsto|text|mathcal|mathbb|mathrm|mathbf|'
    r'hat|bar|vec|dot|tilde|lim|max|min|log|exp|sin|cos|tan|'
    r'alpha|beta|gamma|delta|epsilon|zeta|eta|theta|iota|kappa|lambda|mu|nu|'
    r'xi|pi|rho|sigma|tau|upsilon|phi|chi|psi|omega|'
    r'Alpha|Beta|Gamma|Delta|Epsilon|Zeta|Eta|Theta|Lambda|Mu|Nu|'
    r'Xi|Pi|Rho|Sigma|Tau|Upsilon|Phi|Chi|Psi|Omega)'
)

def is_math(text):
    return bool(LATEX_COMMANDS.search(text))

def extract_paren_content(s, start):
    """Extrait contenu entre parenthèses imbriquées."""
    if start >= len(s) or s[start] != '(':
        return None, -1
    depth = 0
    for i, c in enumerate(s[start:], start):
        if c == '(':
            depth += 1
        elif c == ')':
            depth -= 1
            if depth == 0:
                return s[start+1:i], i
    return None, -1

def normalize_math(text):
    """Normalise le contenu d'une expression math inline."""
    # \mathcal C → \mathcal{C} (sans accolade)
    text = re.sub(r'\\(mathcal|mathbb|mathrm|mathbf|text)\s+([A-Za-z])', r'\\\1{\2}', text)
    
    # ,dt ,dnu -> \,dt
    text = re.sub(r',(\s*)(d\w+)', r'\,\1\2', text)
    
    # ;\sim; ;\circ; -> \sim \circ
    text = re.sub(r';\s*(\\sim|\\circ|\\mid|\\approx|\\equiv|\\cdot)\s*;', r' \1 ', text)
    
    # Échapper les # en \# pour pandoc
    # Mais attention: ne pas échapper si déjà échappé
    text = re.sub(r'(?<!\\)#', r'\\#', text)
    
    # Supprimer les $..$ mal imbriqués
    text = re.sub(r'\$([^$]*)\$', r'\1', text)
    
    return text.strip()

def escape_hash_in_math(line):
    """Échappe les # dans une ligne mathématique."""
    # Échapper # en \# mais pas si déjà échappé
    return re.sub(r'(?<!\\)#', r'\\#', line)

def is_pure_separator(line):
    """Vérifie si une ligne ne contient QUE des séparateurs."""
    stripped = line.strip()
    # Lignes qui ne contiennent que = ou - ou _ (et des espaces)
    if not stripped:
        return False
    return all(c in '=—_–- ' for c in stripped)

def clean_display_lines(lines):
    """Nettoie les lignes d'un bloc display math."""
    result = []
    for line in lines:
        # Si c'est une ligne de pure séparation, on la saute
        if is_pure_separator(line):
            continue
        
        # Nettoyer les séquences longues de = ou - au milieu du texte
        line = re.sub(r'={3,}', ' ', line)
        line = re.sub(r'-{3,}', ' ', line)
        line = re.sub(r'_{3,}', ' ', line)
        
        # Échapper les # dans cette ligne mathématique
        line = escape_hash_in_math(line)
        
        # Nettoyer les espaces multiples
        line = re.sub(r'\s+', ' ', line)
        
        if line.strip():
            result.append(line.rstrip())
    
    return result

def convert_inline_parens(line):
    """Convertit (expr_latex) en $expr_latex$."""
    result = []
    i = 0
    while i < len(line):
        if line[i] == '$':
            if line[i:i+2] == '$$':
                end = line.find('$$', i+2)
                if end != -1:
                    result.append(line[i:end+2])
                    i = end + 2
                    continue
            else:
                end = line.find('$', i+1)
                if end != -1:
                    result.append(line[i:end+1])
                    i = end + 1
                    continue
        if line[i] == '(':
            content, end = extract_paren_content(line, i)
            if content is not None and is_math(content):
                clean = normalize_math(content)
                result.append(f'${clean}$')
                i = end + 1
                continue
        result.append(line[i])
        i += 1
    return ''.join(result)

def is_remote_image(line):
    return bool(re.match(r'!\[.*?\]\(https?://', line.strip()))

def fix_content(content):
    lines = content.split('\n')
    result = []
    i = 0
    in_code_block = False

    while i < len(lines):
        line = lines[i]
        stripped = line.strip()
        
        # Blocs de code
        if stripped.startswith('```'):
            in_code_block = not in_code_block
            result.append(line)
            i += 1
            continue

        if in_code_block:
            result.append(line)
            i += 1
            continue

        # Supprimer images distantes
        if is_remote_image(line):
            i += 1
            continue

        # [ ... ] → $$ ... $$
        if stripped == '[':
            block_lines = []
            i += 1
            while i < len(lines) and lines[i].strip() != ']':
                block_lines.append(lines[i])
                i += 1
            i += 1

            cleaned = clean_display_lines(block_lines)
            if cleaned:
                result.append('')
                result.append('$$')
                result.extend(cleaned)
                result.append('$$')
                result.append('')
            continue

        # $$ display block
        if stripped == '$$':
            block_lines = []
            i += 1
            while i < len(lines) and lines[i].strip() != '$$':
                block_lines.append(lines[i])
                i += 1
            i += 1

            cleaned = clean_display_lines(block_lines)
            if cleaned:
                result.append('')
                result.append('$$')
                result.extend(cleaned)
                result.append('$$')
                result.append('')
            continue

        # Inline math
        # Pour les lignes normales, on échappe aussi les # si nécessaire
        line = escape_hash_in_math(line)
        result.append(convert_inline_parens(line))
        i += 1

    # Éviter les lignes vides multiples
    cleaned_result = []
    prev_empty = False
    for line in result:
        if line == '':
            if not prev_empty:
                cleaned_result.append(line)
            prev_empty = True
        else:
            cleaned_result.append(line)
            prev_empty = False
    
    return '\n'.join(cleaned_result)

def process_file(input_path, output_path=None):
    input_file = Path(input_path)
    if not input_file.exists():
        print(f"Erreur: '{input_path}' introuvable", file=sys.stderr)
        return False
    content = input_file.read_text(encoding='utf-8')
    fixed   = fix_content(content)
    out = Path(output_path) if output_path else \
          input_file.parent / f"{input_file.stem}_fixed{input_file.suffix}"
    out.write_text(fixed, encoding='utf-8')
    print(f"✓ {input_file} → {out}")
    return True

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: python fix_latex_smart.py input.md [output.md]")
        sys.exit(1)
    sys.exit(0 if process_file(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else None) else 1)
