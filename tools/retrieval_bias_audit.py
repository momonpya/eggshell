#!/usr/bin/env python3
"""Measure segment-count score drift on fixed unrelated multilingual texts.

This is a controlled null diagnostic. It does not establish real false-positive
rates or recall and never changes the production threshold.
"""
import argparse
import json
import math
from pathlib import Path
import selectors
import shutil
import struct
import subprocess

from prepare_context_candidate import input_manifest, sha


TEXTS = {
    'english': [
        'The bakery mixes flour, water and yeast before baking bread.',
        'Visitors buy museum tickets and study the painted landscape.',
        'Rain and strong coastal winds affect the afternoon picnic.',
        'Gardeners grow tomatoes and water the plants in summer.',
    ],
    'japanese': [
        'パン屋では小麦粉と水と酵母を混ぜてパンを焼きます。',
        '来館者は美術館の入場券を買い風景画を鑑賞します。',
        '海岸の強い風と雨で午後のピクニックを延期しました。',
        '庭では夏にトマトを育てて毎朝植物に水を与えます。',
    ],
    'korean': [
        '빵집에서는 밀가루와 물과 효모를 섞은 다음 빵을 굽습니다.',
        '방문객들은 미술관 입장권을 사고 풍경화를 감상합니다.',
        '해안의 강한 바람과 비 때문에 오후 소풍을 연기했습니다.',
        '정원에서는 여름에 토마토를 재배하고 매일 아침 물을 줍니다.',
    ],
    'cyrillic': [
        'В пекарне смешивают муку, воду и дрожжи перед выпечкой хлеба.',
        'Посетители покупают билеты в музей и рассматривают пейзажи.',
        'Сильный прибрежный ветер и дождь мешают дневному пикнику.',
        'Садоводы выращивают помидоры и поливают растения летом.',
    ],
}

QUESTIONS = {
    'english': ['How does the kernel schedule threads?', 'How is a cryptographic digest computed?',
        'Why does the compiler reject this type?', 'How is a theorem proved by induction?',
        'How are file permissions checked?', 'What controls network congestion?',
        'How is the stack pointer restored?', 'How are database transactions isolated?'],
    'japanese': ['カーネルはスレッドをどうスケジュールしますか。', '暗号学的ハッシュはどう計算しますか。',
        'コンパイラがこの型を拒否する理由は何ですか。', '帰納法で定理をどう証明しますか。',
        'ファイルのアクセス権限をどう確認しますか。', 'ネットワークの輻輳を何が制御しますか。',
        'スタックポインタをどう復元しますか。', 'データベースのトランザクションをどう分離しますか。'],
    'korean': ['커널은 스레드를 어떻게 스케줄합니까?', '암호학적 해시는 어떻게 계산합니까?',
        '컴파일러가 이 형식을 거부하는 이유는 무엇입니까?', '귀납법으로 정리를 어떻게 증명합니까?',
        '파일 접근 권한을 어떻게 검사합니까?', '네트워크 혼잡은 무엇이 제어합니까?',
        '스택 포인터를 어떻게 복원합니까?', '데이터베이스 트랜잭션을 어떻게 격리합니까?'],
    'cyrillic': ['Как ядро планирует потоки?', 'Как вычисляется криптографический хеш?',
        'Почему компилятор отвергает этот тип?', 'Как доказать теорему индукцией?',
        'Как проверяются права доступа к файлу?', 'Что управляет перегрузкой сети?',
        'Как восстанавливается указатель стека?', 'Как изолируются транзакции базы данных?'],
}


def write(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')


class Encoder:
    def __init__(self, python, script, model, models, output, label):
        self.output = output; self.label = label; self.serial = 0
        self.log = (output / (label + '-stderr')).open('wb')
        self.process = subprocess.Popen([str(python), '-B', str(script), model, str(models), '4',
            str(output / (label + '.guard')), 'search'], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=self.log, text=True)

    def exchange(self, request):
        prefix = self.output / f'{self.label}-{self.serial:03}'
        self.serial += 1
        write(prefix.with_suffix('.request.json'), request)
        self.process.stdin.write(json.dumps(request, separators=(',', ':')) + '\n'); self.process.stdin.flush()
        with selectors.DefaultSelector() as selector:
            selector.register(self.process.stdout, selectors.EVENT_READ)
            if not selector.select(timeout=60):
                raise TimeoutError('Numerical diagnostic did not reply')
        line = self.process.stdout.readline()
        prefix.with_suffix('.reply.json').write_text(line)
        result = json.loads(line)
        if 'error' in result:
            raise ValueError(result['error'])
        return result

    def close(self):
        try:
            self.process.stdin.close()
            code = self.process.wait(timeout=3)
            if code:
                raise RuntimeError('Numerical diagnostic exited unsuccessfully')
        finally:
            if self.process.poll() is None:
                self.process.kill(); self.process.wait(timeout=3)
            self.log.close()


def packed(vector):
    return struct.pack('<' + 'd' * len(vector), *vector).hex()


def encode(python, script, inputs, support, output, label, texts):
    child = Encoder(python, script, inputs['model'], support / 'models', output, label)
    groups = []; coverage = []
    try:
        for start in range(0, len(texts), 16):
            result = child.exchange(dict(texts=texts[start:start + 16]))
            if label == 'ordinary':
                groups.extend([[packed(vector)] for vector in result['vectors']])
            else:
                groups.extend([[packed(vector) for vector in group] for group in result['vectors']])
                coverage.extend(result['coverage'])
        if len(groups) != len(texts) or any(not group for group in groups):
            raise ValueError('The encoder omitted an input group')
        return groups, coverage
    finally:
        child.close()


def quantile(values, fraction):
    return sorted(values)[max(0, math.ceil(len(values) * fraction) - 1)]


def summary(rows):
    values = [row['completeScore'] for row in rows]
    return dict(n=len(rows), ordinaryPass=sum(row['ordinaryScore'] >= .38 for row in rows),
        completePass=sum(score >= .38 for score in values), median=quantile(values, .5),
        q95=quantile(values, .95), q99=quantile(values, .99), maximum=max(values))


def run(args):
    output = args.output.resolve(); output.mkdir(parents=True, exist_ok=False, mode=0o700)
    source = args.source.resolve(); build = args.build.resolve(); support = args.support.resolve()
    candidate = build / 'checkout/runtime/embedding.py'; ordinary = source / 'runtime/embedding.py'
    frozen = {str(path): sha(path) for path in [candidate, ordinary, source / '.lake/build/bin/eggshell']}
    inputs = json.loads((build / 'encoder-inputs.json').read_text())
    if input_manifest(support) != inputs:
        raise ValueError('The pinned encoder assets changed')
    sources = []
    for language, sentences in TEXTS.items():
        for length in [96, 256, 512]:
            for variant, sentence in enumerate(sentences):
                text = ((sentence + ' ') * (length // len(sentence) + 2))[:length]
                sources.append(dict(language=language, characters=len(text), variant=variant, text=text))
    queries = []
    for language, questions in QUESTIONS.items():
        for index, question in enumerate(questions):
            text = ((question + ' ') * (1 if index % 2 == 0 else 8))[:512].rstrip()
            queries.append(dict(language=language, split='calibration' if index < 4 else 'held-out',
                                topic=index, text=text))
    protocol = dict(sources=sources, queries=queries, sourceWindows='one original window per controlled text',
        threshold=.38, selectedQuantile=.99, label='controlled unrelated domains; no positive/recall labels',
        interpretation='null score diagnostic only; no threshold adoption or general false-positive-rate claim',
        sourceHashes=frozen, encoderInputs=inputs, generationModelCalls=0, productionAdoption=False)
    write(output / 'protocol.json', protocol)
    shutil.copy2(Path(__file__), output / 'runner.py')
    texts = [row['text'] for row in queries + sources]; python = support / 'fastembed-0.8.0/bin/python'
    old, _ = encode(python, ordinary, inputs, support, output, 'ordinary', texts)
    complete, coverage = encode(python, candidate, inputs, support, output, 'complete', texts)
    for row, measured in zip(queries + sources, coverage):
        row['coverage'] = measured
    if len(coverage) != len(texts) or any(not row['completeTokenOffsets'] for row in coverage):
        raise ValueError('The numerical diagnostic omitted complete token offsets')
    scorer = Encoder(python, candidate, inputs['model'], support / 'models', output, 'score')
    rows = []
    try:
        for index, query in enumerate(queries):
            before = scorer.exchange(dict(queries=old[index], candidates=old[len(queries):]))['scores']
            after = scorer.exchange(dict(queries=complete[index], candidates=complete[len(queries):]))['scores']
            prefix = scorer.exchange(dict(queries=complete[index],
                candidates=[group[:1] for group in complete[len(queries):]]))['scores']
            if len(before) != len(sources) or len(after) != len(sources):
                raise ValueError('The numerical scorer omitted a controlled source')
            for position, doc in enumerate(sources):
                if after[position] < prefix[position]:
                    raise ValueError('Expanding the same vector set reduced its maximum')
                rows.append(dict(query=index, source=position, split=query['split'],
                    queryLanguage=query['language'], sourceLanguage=doc['language'], characters=doc['characters'],
                    querySegments=len(complete[index]), sourceSegments=len(complete[len(queries) + position]),
                    ordinaryScore=before[position], firstSourceSegmentScore=prefix[position],
                    completeScore=after[position]))
    finally:
        scorer.close()
    calibrated = quantile([row['completeScore'] for row in rows if row['split'] == 'calibration'], .99)
    cells = []
    for split in ['calibration', 'held-out']:
        for field in ['sourceSegments', 'querySegments', 'sourceLanguage', 'characters']:
            for value in sorted({row[field] for row in rows}):
                subset = [row for row in rows if row['split'] == split and row[field] == value]
                if subset:
                    cells.append(dict(split=split, field=field, value=value, **summary(subset)))
    write(output / 'inputs-with-coverage.json', dict(queries=queries, sources=sources))
    write(output / 'scores.json', rows)
    held = [row for row in rows if row['split'] == 'held-out']
    if any(sha(Path(path)) != expected for path, expected in frozen.items()) or input_manifest(support) != inputs:
        raise ValueError('The read-only score audit changed a runtime or model asset')
    result = dict(passed=True, pairs=len(rows), cells=cells,
        calibrationOnlyQ99=calibrated, heldOutCount=len(held),
        heldOutPassingQ99=sum(row['completeScore'] >= calibrated for row in held),
        heldOut=summary(held), thresholdChanged=False, generationModelCalls=0, productionAdoption=False)
    write(output / 'result.json', result)
    print(json.dumps(dict(passed=True, pairs=len(rows), calibrationOnlyQ99=calibrated, heldOut=result['heldOut'])))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ['source', 'build', 'support', 'output']:
        parser.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args()
    try:
        run(args)
    except Exception as error:
        if args.output.is_dir():
            write(args.output / 'failure.json', dict(error=f'{type(error).__name__}: {error}'))
        raise


if __name__ == '__main__':
    main()
