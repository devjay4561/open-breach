/** Durable local saves. A resolved write has committed and passed a read-back check. */
// Keep the legacy database id intentionally so existing players retain their saves.
const DATABASE = 'project-breach-v1';
const DATABASE_VERSION = 2;
const REPLAY_METADATA = 'replay-metadata';
const STORES = new Set(['settings', 'progress', 'plans', 'replays', REPLAY_METADATA]);
const MAX_REPLAY_BYTES = 20 * 1024 * 1024;
const MAX_LIBRARY_BYTES = 100 * 1024 * 1024;
const MAX_REPLAYS = 10;
const COMPETITION_PREFIX = 'cqb-competition:';
const SHOOT_HOUSE_IDS = new Set(['SH01','SH02','SH03','SH04','SH05_PRECISION','SH05_HIGH_INTENSITY']);

export class BreachStorageError extends Error {
  constructor(message, code = 'STORAGE_ERROR', cause) {
    super(message);
    this.name = 'BreachStorageError';
    this.code = code;
    if (cause) this.cause = cause;
  }
}

function storageError(error) {
  if (error instanceof BreachStorageError) return error;
  const name = error?.name;
  if (name === 'QuotaExceededError') {
    return new BreachStorageError('브라우저 저장 공간이 부족합니다. 저장된 리플레이를 삭제한 뒤 다시 시도하세요.', 'QUOTA_EXCEEDED', error);
  }
  if (name === 'SecurityError' || name === 'NotAllowedError') {
    return new BreachStorageError('브라우저에서 로컬 저장소 접근을 차단했습니다. 사이트의 저장소 권한을 확인하세요.', 'STORAGE_UNAVAILABLE', error);
  }
  if (name === 'DataCloneError') {
    return new BreachStorageError('저장 데이터 형식이 올바르지 않습니다.', 'INVALID_DATA', error);
  }
  return new BreachStorageError('로컬 저장에 실패했습니다. 브라우저 저장소 상태를 확인하고 다시 시도하세요.', 'STORAGE_ERROR', error);
}

function jsonCopy(value) {
  try {
    const serialized = JSON.stringify(value);
    if (serialized === undefined) throw new Error('Missing JSON data');
    return JSON.parse(serialized);
  } catch (error) {
    throw new BreachStorageError('저장할 데이터가 유효한 JSON이 아닙니다.', 'INVALID_DATA', error);
  }
}

function byteSize(data) {
  return new TextEncoder().encode(JSON.stringify(data)).byteLength;
}

function competitionEntry(input) {
  const invalid = () => { throw new BreachStorageError('Invalid local competition record.', 'COMPETITION_INVALID'); };
  if (!input || typeof input !== 'object' || Array.isArray(input) || !SHOOT_HOUSE_IDS.has(input.mission)
    || typeof input.condition_key !== 'string' || !input.condition_key.startsWith('run:') || input.condition_key.length>65536
    || input.id!==COMPETITION_PREFIX+input.condition_key || input.kind!=='cqb-competition'
    || typeof input.elapsed!=='number' || !Number.isFinite(input.elapsed) || input.elapsed<=0
    || typeof input.quality!=='number' || !Number.isFinite(input.quality) || input.quality<=0 || input.quality>1
    || !Number.isSafeInteger(input.known) || input.known<1 || input.known>512
    || typeof input.adjusted_time!=='number' || !Number.isFinite(input.adjusted_time)
    || input.adjusted_time!==input.elapsed/Math.max(input.quality,.125)) invalid();
  let conditions;
  try { conditions=JSON.parse(input.condition_key.slice(4)); } catch { invalid(); }
  if (!conditions || typeof conditions!=='object' || Array.isArray(conditions) || conditions.mission!==input.mission
    || Object.keys(conditions).some(key=>!['mission','seed','variant','modifiers','loadout','roster'].includes(key))
    || !Number.isSafeInteger(conditions.seed) || conditions.seed<0 || conditions.seed>2147483647
    || typeof conditions.variant!=='string' || !conditions.variant || !Array.isArray(conditions.modifiers)
    || conditions.modifiers.some(value=>typeof value!=='string')
    || !conditions.loadout || typeof conditions.loadout!=='object' || Array.isArray(conditions.loadout)
    || !Array.isArray(conditions.roster) || conditions.roster.length>4) invalid();
  // Persist the condition key and aggregate feedback only. Raw NPCs, room
  // states, paths, events and private measurements are never copied here.
  return {id:input.id,kind:'cqb-competition',mission:input.mission,condition_key:input.condition_key,
    elapsed:input.elapsed,quality:input.quality,known:input.known,adjusted_time:input.adjusted_time};
}

function competitionRecord(input) {
  const entry=competitionEntry(input);
  if (!Number.isSafeInteger(input.attempts) || input.attempts<1 || !Number.isSafeInteger(input.version) || input.version<1
    || typeof input.updatedAt!=='number' || !Number.isFinite(input.updatedAt) || input.updatedAt<0) {
    throw new BreachStorageError('Invalid local competition record.', 'COMPETITION_INVALID');
  }
  return {...entry,attempts:input.attempts,version:input.version,updatedAt:input.updatedAt};
}

/** Adapter contract for a future Steam implementation. The game constructs
 * the local adapter below; this interface performs no SDK or network calls. */
export class LeaderboardAdapter {
  async submitScore() { throw new BreachStorageError('Leaderboard adapter is not implemented.', 'LEADERBOARD_UNAVAILABLE'); }
  async listScores() { throw new BreachStorageError('Leaderboard adapter is not implemented.', 'LEADERBOARD_UNAVAILABLE'); }
}

export function createLeaderboardAdapter(storage, adapter) {
  if (adapter) {
    if (typeof adapter.submitScore!=='function' || typeof adapter.listScores!=='function') throw new BreachStorageError('Invalid leaderboard adapter.', 'LEADERBOARD_UNAVAILABLE');
    return adapter;
  }
  return Object.freeze({kind:'local',submitScore:entry=>storage.saveShootHouseScore(entry),listScores:async conditionKey=>{
    if (typeof conditionKey!=='string' || !conditionKey.startsWith('run:')) return [];
    const record=await storage.get('progress',COMPETITION_PREFIX+conditionKey);
    if (!record || record.kind!=='cqb-competition') return [];
    return [competitionRecord(record)];
  }});
}

function replayMetadata(record) {
  const { data, ...metadata } = record;
  metadata.bytes = Number.isFinite(record.bytes) && record.bytes >= 0 ? record.bytes : byteSize(data);
  metadata.seed = record.seed ?? data?.seed ?? null;
  metadata.variant = record.variant || data?.variant || 'standard';
  return metadata;
}

function newId() {
  if (globalThis.crypto?.randomUUID) return globalThis.crypto.randomUUID();
  if (!globalThis.crypto?.getRandomValues) {
    throw new BreachStorageError('이 브라우저에서는 안전한 저장 ID를 생성할 수 없습니다.', 'STORAGE_UNAVAILABLE');
  }
  const bytes = globalThis.crypto.getRandomValues(new Uint8Array(16));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  const hex = Array.from(bytes, value => value.toString(16).padStart(2, '0')).join('');
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

export class BreachStorage {
  constructor() {
    this.database = null;
    this.opening = null;
    this.status = 'unopened';
    this.lastError = null;
  }

  /** Opens or upgrades the database. Rejects if persistence is unavailable. */
  async open() {
    if (this.database) return this.database;
    if (this.opening) return this.opening;
    this.opening = new Promise((resolve, reject) => {
      let request;
      let settled = false;
      let upgradeFailure;
      const fail = error => {
        if (settled) return;
        settled = true;
        this.status = 'unavailable';
        this.lastError = storageError(error);
        reject(this.lastError);
      };
      try {
        if (!globalThis.indexedDB) {
          throw new BreachStorageError('이 브라우저에서는 로컬 저장소를 사용할 수 없습니다.', 'STORAGE_UNAVAILABLE');
        }
        request = globalThis.indexedDB.open(DATABASE, DATABASE_VERSION);
      } catch (error) {
        fail(error);
        return;
      }
      request.onupgradeneeded = event => {
        const transaction = request.transaction;
        transaction.onerror = errorEvent => { upgradeFailure ||= errorEvent.target?.error || transaction.error; };
        const abortUpgrade = error => {
          upgradeFailure = error;
          transaction.abort();
        };
        try {
          const database = request.result;
          for (const name of STORES) {
            if (!database.objectStoreNames.contains(name)) database.createObjectStore(name, { keyPath: 'id' });
          }
          if (event.oldVersion < 2) {
            // Read old bodies once, one cursor record at a time. The upgrade
            // commits the index with every existing save, without pruning.
            const metadata = transaction.objectStore(REPLAY_METADATA);
            const cursorRequest = transaction.objectStore('replays').openCursor();
            cursorRequest.onerror = () => { upgradeFailure = cursorRequest.error; };
            cursorRequest.onsuccess = () => {
              const cursor = cursorRequest.result;
              if (!cursor) return;
              try {
                metadata.put(replayMetadata(cursor.value));
                cursor.continue();
              } catch (error) { abortUpgrade(error); }
            };
          }
        } catch (error) { abortUpgrade(error); }
      };
      request.onerror = () => fail(upgradeFailure || request.error);
      request.onblocked = () => fail(new BreachStorageError('다른 게임 탭이 저장소 변경을 막고 있습니다. 다른 탭을 닫고 다시 시도하세요.', 'STORAGE_BLOCKED'));
      request.onsuccess = () => {
        const database = request.result;
        if (settled) {
          database.close();
          return;
        }
        settled = true;
        this.database = database;
        this.status = 'ready';
        this.lastError = null;
        database.onversionchange = () => {
          database.close();
          if (this.database === database) this.database = null;
          this.status = 'unopened';
        };
        database.onclose = () => {
          if (this.database === database) {
            this.database = null;
            this.status = 'unopened';
          }
        };
        resolve(database);
      };
    });
    try {
      return await this.opening;
    } finally {
      this.opening = null;
    }
  }

  async _transaction(name, mode, work) {
    const names = Array.isArray(name) ? name : [name];
    if (!names.length || names.some(value => !STORES.has(value))) throw new BreachStorageError(`알 수 없는 저장 영역: ${name}`, 'INVALID_STORE');
    const database = await this.open();
    return new Promise((resolve, reject) => {
      let transaction;
      let result;
      let failure;
      const rejectWith = error => {
        this.lastError = storageError(error);
        reject(this.lastError);
      };
      try {
        transaction = database.transaction(names, mode);
        transaction.oncomplete = () => resolve(result);
        transaction.onerror = event => { failure ||= event.target?.error || transaction.error; };
        transaction.onabort = () => rejectWith(failure || transaction.error || new Error('Transaction aborted'));
        const context = {
          result: value => { result = value; },
          store: value => transaction.objectStore(value),
          fail: error => {
            failure = error;
            try { transaction.abort(); } catch { rejectWith(error); }
          },
        };
        work(transaction.objectStore(names[0]), context);
      } catch (error) {
        failure = error;
        if (transaction) {
          try { transaction.abort(); } catch { rejectWith(error); }
        } else rejectWith(error);
      }
    });
  }

  async get(store, id) {
    return this._transaction(store, 'readonly', (objectStore, context) => {
      const request = objectStore.get(id);
      request.onsuccess = () => context.result(request.result);
    });
  }

  async all(store) {
    return this._transaction(store, 'readonly', (objectStore, context) => {
      const request = objectStore.getAll();
      request.onsuccess = () => context.result(request.result);
    });
  }

  /** Lists save details without cloning replay bodies from IndexedDB. */
  async listReplays() {
    return this.all(REPLAY_METADATA);
  }

  /** Operator choices follow a persistent roster identity, independent of mission slots. */
  async operatorProfiles() {
    const record = await this.get('settings', 'operator-profiles');
    return record?.data && typeof record.data === 'object' && !Array.isArray(record.data) ? jsonCopy(record.data) : {};
  }

  /** Serialized IndexedDB upsert preserves other operators edited in another tab. */
  async saveOperatorProfile(rosterId, profile) {
    if (typeof rosterId !== 'string' || !/^[A-Za-z][A-Za-z0-9_-]{0,63}$/.test(rosterId)) {
      throw new BreachStorageError('대원 ID가 올바르지 않습니다.', 'INVALID_DATA');
    }
    const data = jsonCopy(profile);
    if (!data || typeof data !== 'object' || Array.isArray(data) || byteSize(data) > 16 * 1024) {
      throw new BreachStorageError('대원 장비 형식이 올바르지 않습니다.', 'INVALID_DATA');
    }
    const record = await this._transaction('settings', 'readwrite', (objectStore, context) => {
      const request = objectStore.get('operator-profiles');
      request.onsuccess = () => {
        try {
          const previous = request.result?.data || {};
          const next = { id: 'operator-profiles', schema_version: 1, version: (request.result?.version || 0) + 1, updatedAt: new Date().toISOString(), data: { ...previous, [rosterId]: data } };
          if (Object.keys(next.data).length > 64) throw new BreachStorageError('대원 설정은 최대 64개까지 저장할 수 있습니다.', 'INVALID_DATA');
          objectStore.put(next);
          context.result(next);
        } catch (error) { context.fail(error); }
      };
    });
    const saved = await this.get('settings', record.id);
    if (!saved || JSON.stringify(saved.data?.[rosterId]) !== JSON.stringify(data)) {
      throw new BreachStorageError('대원 장비 저장 후 확인에 실패했습니다. 다른 탭의 변경 여부를 확인하세요.', 'SAVE_VERIFICATION_FAILED');
    }
    return jsonCopy(saved.data[rosterId]);
  }

  async _verify(store, record) {
    const saved = await this.get(store, record.id);
    if (!saved || saved.id !== record.id || JSON.stringify(saved) !== JSON.stringify(record)) {
      const error = new BreachStorageError('저장 후 데이터 확인에 실패했습니다. 다른 탭의 변경 여부를 확인하고 다시 시도하세요.', 'SAVE_VERIFICATION_FAILED');
      this.lastError = error;
      throw error;
    }
    return saved;
  }

  async put(store, record) {
    const copy = jsonCopy(record);
    if (!copy || typeof copy !== 'object' || Array.isArray(copy) || typeof copy.id !== 'string' || !copy.id) {
      throw new BreachStorageError('저장 데이터에 유효한 ID가 필요합니다.', 'INVALID_DATA');
    }
    const names = store === 'replays' ? [store, REPLAY_METADATA] : store;
    await this._transaction(names, 'readwrite', (objectStore, context) => {
      objectStore.put(copy);
      if (store === 'replays') context.store(REPLAY_METADATA).put(replayMetadata(copy));
    });
    return this._verify(store, copy);
  }

  /** Best adjusted time and attempt count update atomically across tabs.
   * Existing DB v2 stores and all legacy progress IDs remain untouched. */
  async saveShootHouseScore(input) {
    const entry=competitionEntry(input);
    const record=await this._transaction('progress','readwrite',(objectStore,context)=>{
      const request=objectStore.get(entry.id);
      request.onsuccess=()=>{
        try {
          const previous=request.result;
          if (previous) competitionRecord(previous);
          if (previous?.attempts===Number.MAX_SAFE_INTEGER || previous?.version===Number.MAX_SAFE_INTEGER) throw new BreachStorageError('Invalid local competition record.', 'COMPETITION_INVALID');
          const best=previous&&previous.adjusted_time<=entry.adjusted_time?competitionEntry(previous):entry;
          const next={...best,attempts:(Number.isSafeInteger(previous?.attempts)?previous.attempts:0)+1,
            version:(Number.isSafeInteger(previous?.version)?previous.version:0)+1,updatedAt:Date.now()};
          objectStore.put(next);context.result(next);
        } catch(error) { context.fail(error); }
      };
    });
    const saved=await this.get('progress',record.id);
    // A second tab may commit an even better record before read-back. It is
    // a valid verification if its monotonic counters include this write.
    if (!saved || saved.condition_key!==record.condition_key || saved.version<record.version || saved.attempts<record.attempts || saved.adjusted_time>record.adjusted_time) {
      throw new BreachStorageError('Local competition read-back failed.', 'COMPETITION_SAVE_FAILED');
    }
    return competitionRecord(saved);
  }

  async remove(store, id) {
    const names = store === 'replays' ? [store, REPLAY_METADATA] : store;
    await this._transaction(names, 'readwrite', (objectStore, context) => {
      objectStore.delete(id);
      if (store === 'replays') context.store(REPLAY_METADATA).delete(id);
    });
    if (await this.get(store, id) !== undefined) {
      throw new BreachStorageError('삭제 후 데이터 확인에 실패했습니다. 다시 시도하세요.', 'DELETE_VERIFICATION_FAILED');
    }
    return true;
  }

  /** Atomic optimistic concurrency check, including across independent tabs. */
  async saveSettings(settings, expectedVersion = 0) {
    if (!Number.isSafeInteger(expectedVersion) || expectedVersion < 0) {
      throw new BreachStorageError('설정 버전이 올바르지 않습니다.', 'INVALID_VERSION');
    }
    const data = jsonCopy(settings);
    const record = await this._transaction('settings', 'readwrite', (objectStore, context) => {
      const request = objectStore.get('current');
      request.onsuccess = () => {
        try {
          const actualVersion = request.result?.version || 0;
          if (actualVersion !== expectedVersion) {
            const error = new BreachStorageError('다른 탭에서 설정이 변경되었습니다. 최신 설정을 불러온 뒤 다시 저장하세요.', 'SETTINGS_CONFLICT');
            error.actualVersion = actualVersion;
            error.expectedVersion = expectedVersion;
            context.fail(error);
            return;
          }
          const next = { id: 'current', version: actualVersion + 1, updatedAt: new Date().toISOString(), data };
          objectStore.put(next);
          context.result(next);
        } catch (error) { context.fail(error); }
      };
    });
    return this._verify('settings', record);
  }

  /** Stores one replay and prunes the oldest saves in the same transaction. */
  async saveReplay(data) {
    const replay = jsonCopy(data);
    if (!replay || typeof replay !== 'object' || Array.isArray(replay)) {
      throw new BreachStorageError('리플레이 형식이 올바르지 않습니다.', 'INVALID_REPLAY');
    }
    const bytes = byteSize(replay);
    if (bytes > MAX_REPLAY_BYTES) {
      throw new BreachStorageError('리플레이는 최대 20 MB까지 저장할 수 있습니다.', 'REPLAY_TOO_LARGE');
    }
    const mission = replay.mapId ?? replay.map_id ?? replay.mission_id ?? replay.mission;
    const record = {
      id: newId(),
      createdAt: new Date().toISOString(),
      bytes,
      data: replay,
      mapId: typeof mission === 'string' ? mission : (mission?.id || ''),
      duration: Number.isFinite(replay.duration) ? Math.max(0, replay.duration) : 0,
      complete: replay.complete === true,
      seed: Number.isSafeInteger(replay.seed) ? replay.seed : null,
      variant: typeof replay.variant === 'string' ? replay.variant : 'standard',
      modifiers: Array.isArray(replay.modifiers) ? [...new Set(replay.modifiers)].sort() : [],
      loadout: replay.loadout && typeof replay.loadout === 'object' ? replay.loadout : {},
    };
    await this._transaction(['replays', REPLAY_METADATA], 'readwrite', (objectStore, context) => {
      const metadataStore = context.store(REPLAY_METADATA);
      objectStore.put(record);
      metadataStore.put(replayMetadata(record));
      const request = metadataStore.getAll();
      request.onsuccess = () => {
        try {
          const records = request.result.filter(item => item.id !== record.id);
          records.sort((a, b) => String(a.createdAt).localeCompare(String(b.createdAt)) || String(a.id).localeCompare(String(b.id)));
          records.push(record);
          let total = records.reduce((sum, item) => sum + item.bytes, 0);
          while (records.length > MAX_REPLAYS || total > MAX_LIBRARY_BYTES) {
            const oldest = records.shift();
            total -= oldest.bytes;
            objectStore.delete(oldest.id);
            metadataStore.delete(oldest.id);
          }
        } catch (error) { context.fail(error); }
      };
    });
    return this._verify('replays', record);
  }
}
