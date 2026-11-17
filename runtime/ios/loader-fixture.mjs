import { isAbsolute, join } from 'node:path';
import { lstat, writeFile } from 'node:fs/promises';

// App-owned test plugin. It never loads an agent, model, subprocess or profile.
export const name = 'ios-loader-fixture';

export async function apply(ctx, config) {
  if (!config || !isAbsolute(config.directory) || !/^[a-f0-9]{64}$/.test(config.challenge)) {
    throw new Error('IOS_LOADER_FIXTURE_INPUT_INVALID');
  }
  const directory = await lstat(config.directory);
  if (!directory.isDirectory() || directory.isSymbolicLink()) throw new Error('IOS_LOADER_FIXTURE_DIRECTORY_INVALID');
  const activated = join(config.directory, 'activated.json');
  const disposed = join(config.directory, 'disposed.json');
  ctx.effect(() => async () => {
    await writeFile(disposed, JSON.stringify({ challenge: config.challenge, disposed: true }),
      { flag: 'wx', mode: 0o600 });
  }, 'ios-loader-fixture.dispose');
  if (config.fail === true) {
    await writeFile(join(config.directory, 'failure-entered.json'),
      JSON.stringify({ challenge: config.challenge, failureEntered: true }),
      { flag: 'wx', mode: 0o600 });
    throw new Error('IOS_LOADER_FIXTURE_EXPECTED_FAILURE');
  }
  await writeFile(activated, JSON.stringify({ challenge: config.challenge, activated: true }),
    { flag: 'wx', mode: 0o600 });
  ctx.provide('iosLoaderProbe', Object.freeze({ challenge: config.challenge, activated: true }));
}
