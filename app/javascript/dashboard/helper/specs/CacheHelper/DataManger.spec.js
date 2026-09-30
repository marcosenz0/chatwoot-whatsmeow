import { openDB, deleteDB } from 'idb';
import { DataManager } from '../../CacheHelper/DataManager';
import { DATA_VERSION } from '../../CacheHelper/version';

describe('DataManager', () => {
  const accountId = 'test-account';
  let dataManager;

  beforeEach(async () => {
    dataManager = new DataManager(accountId);
    await dataManager.initDb();
  });

  afterEach(async () => {
    const tx = dataManager.db.transaction(
      dataManager.modelsToSync,
      'readwrite'
    );
    dataManager.modelsToSync.forEach(modelName => {
      tx.objectStore(modelName).clear();
    });
    await tx.done;
  });

  describe('initDb', () => {
    it('should stop waiting when an older tab blocks the upgrade, then recover after it closes', async () => {
      const dbName = 'cw-store-blocked-account';
      const legacyDb = await openDB(dbName, 1, {
        upgrade(db) {
          db.createObjectStore('cache-keys');
          db.createObjectStore('inbox', { keyPath: 'id' });
        },
      });
      const blockedManager = new DataManager('blocked-account');

      await expect(blockedManager.initDb()).rejects.toThrow(
        'Local cache upgrade is blocked by another tab'
      );
      legacyDb.close();
      const recoveredDb = await openDB(dbName, DATA_VERSION);
      await vi.waitFor(() => expect(blockedManager.db).not.toBeNull());
      await blockedManager.push({ modelName: 'inbox', data: { id: 1 } });
      expect(await blockedManager.get({ modelName: 'inbox' })).toEqual([
        { id: 1 },
      ]);
      recoveredDb.close();
      blockedManager.db.close();
      await deleteDB(dbName);
    });

    it('should release its connection when another tab upgrades the cache', async () => {
      const manager = new DataManager('upgrade-account');
      await manager.initDb();
      const upgradedDb = await openDB(
        'cw-store-upgrade-account',
        DATA_VERSION + 1
      );

      expect(manager.db).toBeNull();
      upgradedDb.close();
      await deleteDB('cw-store-upgrade-account');
    });

    it('should initialize the database', async () => {
      expect(dataManager.db).not.toBeNull();
    });

    it('should return the same instance of the database', async () => {
      const db1 = await dataManager.initDb();
      const db2 = await dataManager.initDb();
      expect(db1).toBe(db2);
    });

    it('should add new stores and invalidate stale inbox data from an earlier version', async () => {
      const legacyAccountId = 'legacy-account';
      const dbName = `cw-store-${legacyAccountId}`;
      await deleteDB(dbName);

      // The schema as it shipped before canned responses joined the cached models
      const legacyDb = await openDB(dbName, 1, {
        upgrade(db) {
          db.createObjectStore('cache-keys');
          db.createObjectStore('inbox', { keyPath: 'id' });
          db.createObjectStore('label', { keyPath: 'id' });
          db.createObjectStore('team', { keyPath: 'id' });
        },
      });
      await legacyDb.put('cache-keys', 'existing-key', 'inbox');
      await legacyDb.put('cache-keys', 'label-key', 'label');
      await legacyDb.put('inbox', { id: 1, name: 'Legacy inbox' });
      await legacyDb.put('label', { id: 1, title: 'Existing label' });
      legacyDb.close();

      const legacyManager = new DataManager(legacyAccountId);
      await legacyManager.initDb();

      expect([...legacyManager.db.objectStoreNames]).toContain(
        'canned_response'
      );
      expect(await legacyManager.get({ modelName: 'inbox' })).toEqual([]);
      expect(await legacyManager.getCacheKey('inbox')).toBeUndefined();
      expect(await legacyManager.get({ modelName: 'label' })).toEqual([
        { id: 1, title: 'Existing label' },
      ]);
      expect(await legacyManager.getCacheKey('label')).toBe('label-key');
      legacyManager.db.close();
    });
  });

  describe('validateModel', () => {
    it('should throw an error for empty input', async () => {
      expect(() => {
        dataManager.validateModel();
      }).toThrow();
    });

    it('should throw an error for invalid model', async () => {
      expect(() => {
        dataManager.validateModel('invalid-model');
      }).toThrow();
    });

    it('should not throw an error for valid model', async () => {
      expect(dataManager.validateModel('label')).toBeTruthy();
    });
  });

  describe('replace', () => {
    it('should replace existing data in the specified model', async () => {
      const inboxData = [
        { id: 1, name: 'inbox-1' },
        { id: 2, name: 'inbox-2' },
      ];
      const newData = [
        { id: 3, name: 'inbox-3' },
        { id: 4, name: 'inbox-4' },
      ];

      await dataManager.push({ modelName: 'inbox', data: inboxData });
      await dataManager.replace({ modelName: 'inbox', data: newData });
      const result = await dataManager.get({ modelName: 'inbox' });
      expect(result).toEqual(newData);
    });

    it('should replace data whose keys overlap the existing rows', async () => {
      const inboxData = [
        { id: 1, name: 'inbox-1' },
        { id: 2, name: 'inbox-2' },
      ];
      const newData = [
        { id: 1, name: 'inbox-1-renamed' },
        { id: 2, name: 'inbox-2-renamed' },
      ];

      await dataManager.push({ modelName: 'inbox', data: inboxData });
      await dataManager.replace({ modelName: 'inbox', data: newData });
      const result = await dataManager.get({ modelName: 'inbox' });
      expect(result).toEqual(newData);
    });
  });

  describe('push', () => {
    it('should add data to the specified model', async () => {
      const inboxData = { id: 1, name: 'inbox-1' };

      await dataManager.push({ modelName: 'inbox', data: inboxData });
      const result = await dataManager.get({ modelName: 'inbox' });
      expect(result).toEqual([inboxData]);
    });

    it('should add multiple items to the specified model if an array of data is provided', async () => {
      const inboxData = [
        { id: 1, name: 'inbox-1' },
        { id: 2, name: 'inbox-2' },
      ];

      await dataManager.push({ modelName: 'inbox', data: inboxData });
      const result = await dataManager.get({ modelName: 'inbox' });
      expect(result).toEqual(inboxData);
    });
  });

  describe('get', () => {
    it('should return all data in the specified model', async () => {
      const inboxData = [
        { id: 1, name: 'inbox-1' },
        { id: 2, name: 'inbox-2' },
      ];

      await dataManager.push({ modelName: 'inbox', data: inboxData });
      const result = await dataManager.get({ modelName: 'inbox' });
      expect(result).toEqual(inboxData);
    });
  });

  describe('setCacheKeys', () => {
    it('should add cache keys for each model', async () => {
      const cacheKeys = { inbox: 'cache-key-1', label: 'cache-key-2' };

      await dataManager.setCacheKeys(cacheKeys);
      const result = await dataManager.getCacheKey('inbox');
      expect(result).toEqual(cacheKeys.inbox);
    });
  });
});
