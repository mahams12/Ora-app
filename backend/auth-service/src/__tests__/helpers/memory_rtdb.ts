import type {
  RtdbQueryLike,
  RtdbRefLike,
  RtdbSnapshotLike,
} from '../../rtdb/rtdb_geo_client';

/**
 * Minimal in-memory Firebase RTDB fake covering the ref/query/transaction
 * surface the geo client uses: child/get/set/update/remove/runTransaction
 * + orderByChild().startAt().endAt() range queries.
 * Null values delete (matches RTDB semantics).
 */

function clone(v: unknown): unknown {
  return v === undefined ? undefined : JSON.parse(JSON.stringify(v));
}

function getAt(root: Record<string, unknown>, path: string[]): unknown {
  let node: unknown = root;
  for (const seg of path) {
    if (node == null || typeof node !== 'object') return undefined;
    node = (node as Record<string, unknown>)[seg];
  }
  return node;
}

function setAt(root: Record<string, unknown>, path: string[], value: unknown) {
  let node = root;
  for (let i = 0; i < path.length - 1; i += 1) {
    const next = node[path[i]];
    if (next == null || typeof next !== 'object') {
      node[path[i]] = {};
    }
    node = node[path[i]] as Record<string, unknown>;
  }
  if (value == null) delete node[path[path.length - 1]];
  else node[path[path.length - 1]] = value;
}

class MemoryRtdbSnapshot implements RtdbSnapshotLike {
  constructor(
    private readonly _val: unknown,
    public readonly key: string | null,
    private readonly orderedKeys?: string[],
  ) {}

  exists(): boolean {
    return this._val != null;
  }

  val(): unknown {
    return clone(this._val);
  }

  forEach(cb: (child: RtdbSnapshotLike) => boolean | void): boolean {
    if (this._val == null || typeof this._val !== 'object') return false;
    const obj = this._val as Record<string, unknown>;
    const keys = this.orderedKeys ?? Object.keys(obj).sort();
    for (const k of keys) {
      if (!(k in obj)) continue;
      if (cb(new MemoryRtdbSnapshot(clone(obj[k]), k)) === true) return true;
    }
    return false;
  }
}

class MemoryRtdbQuery implements RtdbQueryLike {
  private _startAt: string | number | undefined;
  private _endAt: string | number | undefined;
  private _limit: number | undefined;

  constructor(
    private readonly ref: MemoryRtdbRef,
    private readonly childKey: string,
  ) {}

  startAt(v: string | number): RtdbQueryLike {
    this._startAt = v;
    return this;
  }

  endAt(v: string | number): RtdbQueryLike {
    this._endAt = v;
    return this;
  }

  limitToFirst(n: number): RtdbQueryLike {
    this._limit = n;
    return this;
  }

  async get(): Promise<RtdbSnapshotLike> {
    const node = this.ref.resolve();
    const obj =
      node != null && typeof node === 'object'
        ? (node as Record<string, unknown>)
        : {};
    const entries = Object.entries(obj).filter(([, v]) => {
      const kv =
        v != null && typeof v === 'object'
          ? (v as Record<string, unknown>)[this.childKey]
          : undefined;
      if (kv == null) return false;
      if (this._startAt != null && kv < this._startAt) return false;
      if (this._endAt != null && kv > this._endAt) return false;
      return true;
    });
    entries.sort(([ka, va], [kb, vb]) => {
      const ca =
        va != null && typeof va === 'object'
          ? (va as Record<string, unknown>)[this.childKey]
          : undefined;
      const cb =
        vb != null && typeof vb === 'object'
          ? (vb as Record<string, unknown>)[this.childKey]
          : undefined;
      if (ca === cb) return ka < kb ? -1 : ka > kb ? 1 : 0;
      return (ca as string | number) < (cb as string | number) ? -1 : 1;
    });
    const limited = this._limit == null ? entries : entries.slice(0, this._limit);
    const ordered: Record<string, unknown> = {};
    const keys: string[] = [];
    for (const [k, v] of limited) {
      ordered[k] = v;
      keys.push(k);
    }
    return new MemoryRtdbSnapshot(ordered, this.ref.key(), keys);
  }
}

export class MemoryRtdbRef implements RtdbRefLike {
  constructor(
    private readonly root: Record<string, unknown>,
    private readonly path: string[] = [],
  ) {}

  key(): string | null {
    return this.path.length ? this.path[this.path.length - 1] : null;
  }

  child(path: string): RtdbRefLike {
    const segs = path.split('/').filter((s) => s.length > 0);
    return new MemoryRtdbRef(this.root, [...this.path, ...segs]);
  }

  resolve(): unknown {
    return getAt(this.root, this.path);
  }

  async get(): Promise<RtdbSnapshotLike> {
    return new MemoryRtdbSnapshot(clone(this.resolve()), this.key());
  }

  async set(value: unknown): Promise<unknown> {
    setAt(this.root, this.path, clone(value));
    return undefined;
  }

  async update(value: Record<string, unknown>): Promise<unknown> {
    const cur = this.resolve();
    const base =
      cur != null && typeof cur === 'object'
        ? { ...(cur as Record<string, unknown>) }
        : {};
    for (const [k, v] of Object.entries(value)) {
      if (v == null) delete base[k];
      else base[k] = v;
    }
    if (Object.keys(base).length === 0) {
      setAt(this.root, this.path, null);
    } else {
      setAt(this.root, this.path, base);
    }
    return undefined;
  }

  async remove(): Promise<unknown> {
    setAt(this.root, this.path, null);
    return undefined;
  }

  async transaction(update: (current: unknown) => unknown): Promise<{
    committed: boolean;
    snapshot: RtdbSnapshotLike | null;
  }> {
    const current = clone(this.resolve());
    const next = update(current === undefined ? null : current);
    if (next === undefined) {
      return {
        committed: false,
        snapshot: new MemoryRtdbSnapshot(current, this.key()),
      };
    }
    setAt(this.root, this.path, clone(next));
    return {
      committed: true,
      snapshot: new MemoryRtdbSnapshot(next, this.key()),
    };
  }

  orderByChild(key: string): RtdbQueryLike {
    return new MemoryRtdbQuery(this, key);
  }
}

/** Root factory — mirrors `db.ref('/')` usage in the RTDB geo client. */
export function memoryRtdb(): {
  ref(path?: string): RtdbRefLike;
  _root: Record<string, unknown>;
} {
  const root: Record<string, unknown> = {};
  return {
    ref: (path = '/') => new MemoryRtdbRef(root, path.split('/').filter(Boolean)),
    _root: root,
  };
}
