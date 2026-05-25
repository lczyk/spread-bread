#!/usr/bin/env python3
"""Inline `source scripts/<name>.sh` references inside spread yaml templates.

For each line matching `allocate: source scripts/<name>.sh` or
`discard: source scripts/<name>.sh`, substitute the script's content as a
yaml block scalar under the matching key.
"""

import logging
import re
from argparse import ArgumentParser, Namespace
from pathlib import Path

SCRIPTS_DIR = Path("scripts")

# Match e.g. "    allocate: source scripts/spread_allocate_bread.sh"
LINE_RE = re.compile(
    r"^(?P<indent>\s*)(?P<key>allocate|discard):\s*source\s+(?P<path>scripts/[\w.-]+\.sh)\s*$"
)


def main() -> None:
    args = parse_args()
    input_path = Path(args.input)
    output_path = Path(args.output)

    if not input_path.exists():
        logging.error(f"Error: {input_path} does not exist.")
        return

    content = input_path.read_text()
    new_content = inline_scripts(content)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(new_content)
    logging.info(f"Processed {input_path} -> {output_path}")


def parse_args() -> Namespace:
    parser = ArgumentParser(description="Inline allocate/discard scripts into a yaml template")
    parser.add_argument("input", help="path to the .yaml.in template to process")
    parser.add_argument("output", help="path to write the rendered yaml file")
    return parser.parse_args()


def inline_scripts(content: str, yaml_indent: int = 2) -> str:
    out_lines: list[str] = []
    for line in content.splitlines():
        m = LINE_RE.match(line)
        if not m:
            out_lines.append(line)
            continue
        indent = m.group("indent")
        key = m.group("key")
        script_path = Path(m.group("path"))
        if not script_path.exists():
            raise FileNotFoundError(f"Referenced script not found: {script_path}")
        out_lines.append(f"{indent}{key}: |")
        body_indent = indent + " " * yaml_indent
        for script_line in script_path.read_text().splitlines():
            out_lines.append(body_indent + script_line if script_line else body_indent.rstrip())
    return "\n".join(out_lines) + "\n"


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    main()
