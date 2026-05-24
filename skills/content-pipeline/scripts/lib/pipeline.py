#!/usr/bin/env python3
"""pipeline.py — 内容管线 CLI 工具

子命令:
  record-result       — 合并平台分发结果到 RESULTS JSON（stdin/stdout）
  build-juejin-draft  — 构建掘金创建草稿请求 JSON
  build-juejin-publish— 构建掘金发布草稿请求 JSON
  build-wechat-draft  — 构建微信创建草稿请求 JSON
"""
import argparse
import hashlib
import hmac
import json
import re
import sys
import uuid
from pathlib import Path


def _read_content(path: str) -> str:
    if path == '-':
        return sys.stdin.read()
    return Path(path).read_text(encoding='utf-8')


def cmd_record_result(args: argparse.Namespace) -> None:
    results = json.load(sys.stdin)
    entry: dict = {'status': args.status}
    if args.message:
        entry['message'] = args.message
    if args.url:
        entry['url'] = args.url
    if args.health_check:
        entry['health_check'] = args.health_check
    results[args.platform] = entry
    json.dump(results, sys.stdout, ensure_ascii=False)
    sys.stdout.write('\n')


def cmd_build_juejin_draft(args: argparse.Namespace) -> None:
    content = _read_content(args.content_file)
    tag_ids = [t.strip() for t in args.tag_ids.split(',') if t.strip()]

    # 生成摘要：去除 markdown 标记，取前 100 字
    plain = re.sub(r'```[\s\S]*?```', '', content)
    plain = re.sub(r'[#*>`\[\]]', '', plain)
    plain = re.sub(r'\s+', ' ', plain).strip()
    brief = plain[:100]

    payload = {
        'category_id': args.category_id,
        'tag_ids': tag_ids,
        'link_url': '',
        'cover_image': '',
        'title': args.title,
        'brief_content': brief,
        'edit_type': 10,
        'html_content': 'deprecated',
        'mark_content': content,
        'theme_ids': [],
        'column_ids': [],
    }

    if len(args.title) > 80:
        print('[WARN] 标题超过 80 字，掘金可能截断', file=sys.stderr)

    json.dump(payload, sys.stdout, ensure_ascii=False)
    sys.stdout.write('\n')


def cmd_build_juejin_publish(args: argparse.Namespace) -> None:
    payload = {
        'draft_id': args.draft_id,
        'sync_to_org': False,
        'column_ids': [],
        'theme_ids': [],
    }
    json.dump(payload, sys.stdout, ensure_ascii=False)
    sys.stdout.write('\n')


def cmd_build_wechat_draft(args: argparse.Namespace) -> None:
    content = _read_content(args.content_file)
    article = {
        'title': args.title,
        'content': content,
        'need_open_comment': 0,
        'only_fans_can_comment': 0,
    }
    if args.cover_media_id:
        article['thumb_media_id'] = args.cover_media_id

    payload = {'articles': [article]}
    json.dump(payload, sys.stdout, ensure_ascii=False)
    sys.stdout.write('\n')


import os

_CSDN_APP_KEY = os.environ.get('CSDN_APP_KEY', '')
_CSDN_APP_SECRET = os.environ.get('CSDN_APP_SECRET', '')


def cmd_csdn_sign(args: argparse.Namespace) -> None:
    """生成 CSDN API 请求签名及相关 headers"""
    if not _CSDN_APP_KEY or not _CSDN_APP_SECRET:
        print('[ERROR] 请设置环境变量 CSDN_APP_KEY 和 CSDN_APP_SECRET', file=sys.stderr)
        sys.exit(1)

    nonce = str(uuid.uuid4()).replace('-', '')
    timestamp = str(int(__import__('time').time() * 1000))
    string_to_sign = _CSDN_APP_KEY + timestamp + nonce
    signature = hmac.new(
        _CSDN_APP_SECRET.encode('utf-8'),
        string_to_sign.encode('utf-8'),
        hashlib.sha256,
    ).hexdigest().upper()

    payload = {
        'x-ca-key': _CSDN_APP_KEY,
        'x-ca-nonce': nonce,
        'x-ca-timestamp': timestamp,
        'x-ca-signature': signature,
    }
    json.dump(payload, sys.stdout, ensure_ascii=False)
    sys.stdout.write('\n')


def main() -> None:
    parser = argparse.ArgumentParser(description='内容管线工具')
    sub = parser.add_subparsers(dest='command')

    # --- record-result ---
    rr = sub.add_parser('record-result', help='合并平台分发结果')
    rr.add_argument('--platform', required=True)
    rr.add_argument('--status', required=True, choices=['SUCCESS', 'FAIL', 'SKIP'])
    rr.add_argument('--message', default='')
    rr.add_argument('--url', default='')
    rr.add_argument('--health-check', default='')
    rr.set_defaults(func=cmd_record_result)

    # --- build-juejin-draft ---
    bjd = sub.add_parser('build-juejin-draft', help='构建掘金草稿 JSON')
    bjd.add_argument('--title', required=True)
    bjd.add_argument('--content-file', required=True)
    bjd.add_argument('--category-id', default='6809637769959178254')
    bjd.add_argument('--tag-ids', default='')
    bjd.set_defaults(func=cmd_build_juejin_draft)

    # --- build-juejin-publish ---
    bjp = sub.add_parser('build-juejin-publish', help='构建掘金发布 JSON')
    bjp.add_argument('--draft-id', required=True)
    bjp.set_defaults(func=cmd_build_juejin_publish)

    # --- build-wechat-draft ---
    bwd = sub.add_parser('build-wechat-draft', help='构建微信草稿 JSON')
    bwd.add_argument('--title', required=True)
    bwd.add_argument('--content-file', required=True)
    bwd.add_argument('--cover-media-id', default='')
    bwd.set_defaults(func=cmd_build_wechat_draft)

    # --- csdn-sign ---
    sub.add_parser('csdn-sign', help='生成 CSDN API 签名 headers').set_defaults(func=cmd_csdn_sign)

    args = parser.parse_args()
    if not args.command:
        parser.print_help()
        sys.exit(1)
    args.func(args)


if __name__ == '__main__':
    main()
