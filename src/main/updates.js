import { net } from 'electron';
import { compareVersions } from 'compare-versions';

const RELEASES_API = 'https://api.github.com/repos/jkotzker/fromscratch/releases/latest';

/**
 * Returns the newest release tag when it is newer than `currentVersion`, otherwise null.
 * Stays silent on every failure: no releases yet (404), rate limiting, or no network.
 */
export async function getNewerVersion(currentVersion) {
  try {
    const response = await net.fetch(RELEASES_API, {
      headers: { Accept: 'application/vnd.github+json' },
    });

    if (!response.ok) return null;

    const { tag_name: tag } = await response.json();
    if (!tag) return null;

    const latest = String(tag).replace(/^v/, '');
    return compareVersions(latest, currentVersion) === 1 ? latest : null;
  } catch {
    return null;
  }
}
