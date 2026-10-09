import { getWeiboEmoji } from './WeiboText';

export interface WeiboRichToken {
  type: 'text' | 'topic' | 'mention' | 'link' | 'emoji';
  text: string;
  value?: string;
  emojiUrl?: string;
}

/** Parse normalized plain text, never execute server HTML. */
export function parseWeiboText(input: string): WeiboRichToken[] {
  const pattern: RegExp = /(#[^#\n\r]+#)|(@[a-zA-Z0-9_\u4e00-\u9fa5-]+)|(https?:\/\/[^\s<>"'\u4e00-\u9fa5，。！？；、（）【】]+)|(\[[^\]\n]+\])/g;
  const tokens: WeiboRichToken[] = [];
  let lastIndex: number = 0;
  let match: RegExpExecArray | null = pattern.exec(input);
  while (match !== null) {
    if (match.index > lastIndex) { tokens.push({ type: 'text', text: input.substring(lastIndex, match.index) }); }
    let text: string = match[0];
    let consumed: number = text.length;
    if (text.startsWith('#')) {
      tokens.push({ type: 'topic', text: text, value: text.substring(1, text.length - 1) });
    } else if (text.startsWith('@')) {
      tokens.push({ type: 'mention', text: text, value: text.substring(1) });
    } else if (/^https?:/.test(text)) {
      // Sentence punctuation is not part of a URL. Keep it in the next text span.
      text = text.replace(/[.,!?;:]+$/, '');
      consumed = text.length;
      tokens.push({ type: 'link', text: text, value: text });
    } else {
      const name: string = text.substring(1, text.length - 1);
      const url: string | undefined = getWeiboEmoji(name);
      tokens.push({ type: url === undefined ? 'text' : 'emoji', text: text, value: name, emojiUrl: url });
    }
    lastIndex = match.index + consumed;
    pattern.lastIndex = lastIndex;
    match = pattern.exec(input);
  }
  if (lastIndex < input.length) { tokens.push({ type: 'text', text: input.substring(lastIndex) }); }
  return tokens;
}
