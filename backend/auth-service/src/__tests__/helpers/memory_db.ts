/**
 * Multi-collection in-memory Firestore stand-in for unit/integration tests.
 *
 * Transactions are globally serialized (mutex). Concurrent Promise.all callers
 * still exercise domain gates: the loser observes committed state and receives
 * ALREADY_ASSIGNED / STATE_CONFLICT. This proves assignment exclusivity of the
 * service logic; it is not a substitute for a live Firestore emulator race.
 *
 * Query support includes equality/`in` filters, orderBy, startAfter, and limit
 * for Phase 2I ride list keyset pagination (not a full Firestore emulator).
 */
export function memoryDb() {
  /** key = `${collection}/${id}` */
  const store = new Map<string, Record<string, unknown>>();
  let txnChain: Promise<unknown> = Promise.resolve();

  type DocRef = {
    id: string;
    path: string;
    collection: string;
    get: () => Promise<{
      exists: boolean;
      id: string;
      data: () => Record<string, unknown> | undefined;
      ref: DocRef;
    }>;
    set: (value: Record<string, unknown>) => Promise<void>;
    update: (value: Record<string, unknown>) => Promise<void>;
  };

  function makeDoc(collection: string, id: string): DocRef {
    const path = `${collection}/${id}`;
    const ref: DocRef = {
      id,
      path,
      collection,
      async get() {
        const data = store.get(path);
        return {
          exists: data != null,
          id,
          data: () => data,
          ref,
        };
      },
      async set(value: Record<string, unknown>) {
        store.set(path, { ...value });
      },
      async update(value: Record<string, unknown>) {
        const existing = store.get(path);
        if (!existing) throw new Error('NOT_FOUND');
        store.set(path, { ...existing, ...value });
      },
    };
    return ref;
  }

  type OrderBy = { field: string; direction: 'asc' | 'desc' };

  type Query = {
    _collection: string;
    _filters: Array<{ field: string; op: string; value: unknown }>;
    _orderBy: OrderBy[];
    _startAfter: unknown[] | null;
    _limit: number | null;
    where: (field: string, op: string, value: unknown) => Query;
    orderBy: (field: string, direction?: 'asc' | 'desc') => Query;
    startAfter: (...values: unknown[]) => Query;
    limit: (n: number) => Query;
    get: () => Promise<{
      docs: Array<{
        id: string;
        exists: boolean;
        data: () => Record<string, unknown>;
        ref: DocRef;
      }>;
      empty: boolean;
    }>;
  };

  function matchesFilters(
    data: Record<string, unknown>,
    filters: Query['_filters'],
  ): boolean {
    for (const f of filters) {
      if (f.op === '==') {
        if (data[f.field] !== f.value) return false;
      } else if (f.op === 'in') {
        if (!Array.isArray(f.value) || !f.value.includes(data[f.field])) {
          return false;
        }
      } else if (f.op === '<=') {
        if (compareValues(data[f.field], f.value) > 0) return false;
      } else if (f.op === '>=') {
        if (compareValues(data[f.field], f.value) < 0) return false;
      } else {
        return false;
      }
    }
    return true;
  }

  function compareValues(a: unknown, b: unknown): number {
    if (a === b) return 0;
    if (a == null) return -1;
    if (b == null) return 1;
    if (typeof a === 'number' && typeof b === 'number') return a - b;
    const as = String(a);
    const bs = String(b);
    if (as < bs) return -1;
    if (as > bs) return 1;
    return 0;
  }

  function sortRows(
    rows: Array<{ id: string; data: Record<string, unknown> }>,
    orderBy: OrderBy[],
  ): void {
    if (orderBy.length === 0) return;
    rows.sort((ra, rb) => {
      for (const ob of orderBy) {
        let cmp = compareValues(ra.data[ob.field], rb.data[ob.field]);
        if (ob.direction === 'desc') cmp = -cmp;
        if (cmp !== 0) return cmp;
      }
      return 0;
    });
  }

  /** Positive if row is strictly after cursor in ordered result sequence. */
  function compareToCursor(
    row: { data: Record<string, unknown> },
    cursorValues: unknown[],
    orderBy: OrderBy[],
  ): number {
    for (let i = 0; i < orderBy.length; i++) {
      const ob = orderBy[i]!;
      let cmp = compareValues(row.data[ob.field], cursorValues[i]);
      if (ob.direction === 'desc') cmp = -cmp;
      if (cmp !== 0) return cmp;
    }
    return 0;
  }

  function cloneQuery(base: Query): Query {
    const next = makeQuery(base._collection);
    next._filters = [...base._filters];
    next._orderBy = [...base._orderBy];
    next._startAfter = base._startAfter ? [...base._startAfter] : null;
    next._limit = base._limit;
    return next;
  }

  function makeQuery(collection: string): Query {
    const q: Query = {
      _collection: collection,
      _filters: [],
      _orderBy: [],
      _startAfter: null,
      _limit: null,
      where(field, op, value) {
        const next = cloneQuery(q);
        next._filters.push({ field, op, value });
        return next;
      },
      orderBy(field, direction = 'asc') {
        const next = cloneQuery(q);
        next._orderBy.push({
          field,
          direction: direction === 'desc' ? 'desc' : 'asc',
        });
        return next;
      },
      startAfter(...values) {
        const next = cloneQuery(q);
        next._startAfter = values;
        return next;
      },
      limit(n) {
        const next = cloneQuery(q);
        next._limit = n;
        return next;
      },
      async get() {
        const prefix = `${collection}/`;
        let rows: Array<{ id: string; data: Record<string, unknown> }> = [];
        for (const [path, data] of store.entries()) {
          if (!path.startsWith(prefix)) continue;
          const id = path.slice(prefix.length);
          if (matchesFilters(data, q._filters)) rows.push({ id, data });
        }
        sortRows(rows, q._orderBy);
        if (q._startAfter != null && q._orderBy.length > 0) {
          rows = rows.filter(
            (row) => compareToCursor(row, q._startAfter!, q._orderBy) > 0,
          );
        }
        if (q._limit != null) rows = rows.slice(0, q._limit);
        return {
          docs: rows.map((row) => ({
            id: row.id,
            exists: true,
            data: () => row.data,
            ref: makeDoc(collection, row.id),
          })),
          empty: rows.length === 0,
        };
      },
    };
    return q;
  }

  return {
    store,
    seed(collection: string, id: string, value: Record<string, unknown>) {
      store.set(`${collection}/${id}`, { ...value });
    },
    getDoc(collection: string, id: string) {
      return store.get(`${collection}/${id}`);
    },
    collection(name: string) {
      return {
        doc: (id: string) => makeDoc(name, id),
        where: (field: string, op: string, value: unknown) =>
          makeQuery(name).where(field, op, value),
        orderBy: (field: string, direction?: 'asc' | 'desc') =>
          makeQuery(name).orderBy(field, direction),
        limit: (n: number) => makeQuery(name).limit(n),
      };
    },
    async runTransaction<T>(
      fn: (tx: {
        get: (
          refOrQuery: DocRef | Query,
        ) => Promise<
          | {
              exists: boolean;
              id?: string;
              data: () => Record<string, unknown> | undefined;
              ref?: DocRef;
            }
          | {
              docs: Array<{
                id: string;
                data: () => Record<string, unknown>;
                ref: DocRef;
              }>;
            }
        >;
        set: (ref: DocRef, value: Record<string, unknown>) => void;
        update: (ref: DocRef, value: Record<string, unknown>) => void;
      }) => Promise<T>,
    ): Promise<T> {
      const run = async (): Promise<T> => {
        const pending = new Map<string, Record<string, unknown> | null>();
        const tx = {
          async get(refOrQuery: DocRef | Query) {
            if ('_filters' in refOrQuery) {
              const q = refOrQuery as Query;
              const prefix = `${q._collection}/`;
              const docs: Array<{
                id: string;
                data: () => Record<string, unknown>;
                ref: DocRef;
              }> = [];
              const seen = new Set<string>();
              const consider = (
                id: string,
                data: Record<string, unknown> | null | undefined,
              ) => {
                if (!data || seen.has(id)) return;
                if (!matchesFilters(data, q._filters)) return;
                seen.add(id);
                docs.push({
                  id,
                  data: () => data,
                  ref: makeDoc(q._collection, id),
                });
              };
              for (const [path, data] of store.entries()) {
                if (!path.startsWith(prefix)) continue;
                const id = path.slice(prefix.length);
                if (pending.has(path)) {
                  consider(id, pending.get(path) ?? undefined);
                } else {
                  consider(id, data);
                }
              }
              for (const [path, data] of pending.entries()) {
                if (!path.startsWith(prefix) || data == null) continue;
                consider(path.slice(prefix.length), data);
              }
              let rows = docs.map((d) => ({
                id: d.id,
                data: d.data(),
                ref: d.ref,
              }));
              sortRows(rows, q._orderBy);
              if (q._startAfter != null && q._orderBy.length > 0) {
                rows = rows.filter(
                  (row) =>
                    compareToCursor(row, q._startAfter!, q._orderBy) > 0,
                );
              }
              const limited =
                q._limit != null ? rows.slice(0, q._limit) : rows;
              return {
                docs: limited.map((row) => ({
                  id: row.id,
                  data: () => row.data,
                  ref: row.ref,
                })),
                empty: limited.length === 0,
              };
            }
            const ref = refOrQuery as DocRef;
            if (pending.has(ref.path)) {
              const data = pending.get(ref.path);
              return {
                exists: data != null,
                id: ref.id,
                data: () => data ?? undefined,
                ref,
              };
            }
            return ref.get();
          },
          set(ref: DocRef, value: Record<string, unknown>) {
            pending.set(ref.path, { ...value });
          },
          update(ref: DocRef, value: Record<string, unknown>) {
            const base = pending.has(ref.path)
              ? pending.get(ref.path)
              : store.get(ref.path);
            if (!base) throw new Error('NOT_FOUND');
            pending.set(ref.path, { ...base, ...value });
          },
        };
        const result = await fn(tx as never);
        for (const [path, value] of pending.entries()) {
          if (value == null) store.delete(path);
          else store.set(path, value);
        }
        return result;
      };

      const next = txnChain.then(run, run);
      txnChain = next.then(
        () => undefined,
        () => undefined,
      );
      return next;
    },
  };
}

export function throwingDb(message = 'FIRESTORE_UNAVAILABLE') {
  return {
    store: new Map<string, Record<string, unknown>>(),
    collection() {
      return {
        doc() {
          return {
            async get() {
              throw new Error(message);
            },
          };
        },
        where() {
          return {
            where() {
              return this;
            },
            orderBy() {
              return this;
            },
            startAfter() {
              return this;
            },
            limit() {
              return this;
            },
            async get() {
              throw new Error(message);
            },
          };
        },
      };
    },
    async runTransaction() {
      throw new Error(message);
    },
  };
}
