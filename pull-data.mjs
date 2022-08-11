#!/usr/bin/env zx

import 'zx/globals'
import * as JSONStream from 'JSONStream'

echo('Fetching release list...')

const releases = await fetch('https://api.github.com/repos/CleverRaven/Cataclysm-DDA/releases').then(j => j.json())

const latest_build = releases[0].tag_name
await fs.writeJSON('latest-build.json', {latest_build})

const forbidden_tags = [
  'cdda-experimental-2021-07-09-1837', // this release had broken json
  'cdda-experimental-2021-07-09-1719',
]

for (const release of releases) {
  const {tag_name} = release
  const tarball_url = `https://api.github.com/repos/CleverRaven/Cataclysm-DDA/tarball/${encodeURIComponent(tag_name)}`
  if (forbidden_tags.includes(tag_name)) continue

  if (!fs.existsSync(`data/${tag_name}/all.json`)) {
    echo(`Fetching source for build ${tag_name}...`)
    const src_dir = path.join('data', tag_name, 'src')
    await $`mkdir -p ${src_dir}`
    cd(src_dir)
    await $`curl -sL ${tarball_url} | tar xz --strip-components=1`
    echo('Collating JSON...')
    const json_files = await glob('data/json/**/*.json')
    const data = []
    for (const file of json_files) {
      const json = await fs.readJSON(file)
      for (const j of json) j.__filename = file
      data.push(...json)
    }
    const all = {
      build_number: tag_name,
      release,
      data,
    }
    await fs.writeJSON('../all.json', all)

    echo('Compiling lang JSON...')
    await $`mkdir ../lang`

    for (const po_file of await glob('lang/po/*.po')) {
      await $`npx gettext.js ${po_file} ../lang/${path.basename(po_file, '.po')}.json`
    }
    echo('Cleaning up...')
    cd('..')
    await $`rm -rf src`
    cd('../..')
  }
}

function readKey(file, keyPath) {
  return new Promise(resolve => {
    const stream = fs.createReadStream(file).pipe(JSONStream.parse(keyPath))
    stream.once('data', (d) => {
      stream.destroy()
      resolve(d)
    })
  })
}

echo('Collecting info from all builds...')
const builds = await within(async () => {
  cd('data')
  const builds = []
  for (const tag_name of await glob('*', {onlyDirectories: true})) {
    if (tag_name === "latest") continue
    const {prerelease, created_at} = await readKey(path.join(process.cwd(), tag_name, 'all.json'), ['release'])
    const langs = (await glob(path.join(tag_name, 'lang'))).map(f => path.basename(f, '.json'))
    builds.push({
      build_number: tag_name,
      prerelease,
      created_at,
      langs
    })
  }
  builds.sort((a, b) => b.created_at.localeCompare(a.created_at))
  return builds
})
await fs.writeJSON('builds.json', builds)
echo(`Wrote info about ${builds.length} builds to builds.json.`)

await $`mkdir -p data/latest`
await $`ln -f data/${latest_build}/all.json data/latest/all.json`
for (const lang_json of await glob(`data/${latest_build}/lang/*.json`))
  await $`ln -f ${lang_json} data/latest/lang/${path.basename(lang_json)}`

