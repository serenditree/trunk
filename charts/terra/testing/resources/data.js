import faker from 'k6/x/faker';

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// CONST
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
export const NORTH_EAST = {
    lng: 16.450465545555687,
    lat: 48.22369800478231
};

export const SOUTH_WEST = {
    lng: 16.269362792869856,
    lat: 48.193954482542836
};

const DACH_NORTH_EAST = {
    lng: 17.2,
    lat: 55.1
};

const DACH_SOUTH_WEST = {
    lng: 5.5,
    lat: 45.7
};

const ST_HEADERS_PREFIX = 'X-St-'

export const ST_HEADERS = {
    id: ST_HEADERS_PREFIX + 'Id',
    username: ST_HEADERS_PREFIX + 'Username',
    email: ST_HEADERS_PREFIX + 'Email',
    password: ST_HEADERS_PREFIX + 'Password',
    verification: ST_HEADERS_PREFIX + 'Verification',
    verified: ST_HEADERS_PREFIX + 'Verified'
};

export const ST_SORTING = {
    water: 'BY_WATER',
    nubits: 'BY_NUBITS',
    date: 'BY_DATE',
    chance: 'BY_CHANCE'
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// RANDOM
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
export function randomUser() {
    const user = {};
    user[ST_HEADERS.username] = faker.internet.username();
    user[ST_HEADERS.password] = faker.internet.password(true, true, true, true, false, 21);

    return {
        headers: user
    };
}

function randomPoll(optional) {
    let poll = [];
    if (!optional || faker.numbers.intRange(1, 10) > 7) {
        poll = Array.from(
            {length: faker.numbers.intRange(1, 4)},
            () => {
                return {
                    'title': faker.word.loremIpsumSentence(faker.numbers.intRange(1, 4)).replace('.', ''),
                    'options': Array.from(
                        {length: faker.numbers.intRange(1, 4)},
                        () => {
                            return {
                                'text': faker.word.loremIpsumSentence(faker.numbers.intRange(1, 4)).replace('.', ''),
                                'votes': 0
                            }
                        }
                    )
                }
            }
        );
    }
    return poll
}

export function randomOption(pollBySeedResponse) {
    const pollIndex = faker.numbers.intRange(0, pollBySeedResponse.json().length - 1);
    const optionIndex = faker.numbers.intRange(0, pollBySeedResponse.json(`${pollIndex}.options`).length - 1);

    return {
        'poll': pollIndex,
        'option': optionIndex
    }

}

export function randomSeed() {
    return JSON.stringify({
        'polls': randomPoll(true),
        'location': {
            'lng': faker.numbers.float32Range(SOUTH_WEST.lng, NORTH_EAST.lng),
            'lat': faker.numbers.float32Range(SOUTH_WEST.lat, NORTH_EAST.lat)
        },
        'title': faker.word.loremIpsumSentence(faker.numbers.intRange(1, 4)).replace('.', ''),
        'text': faker.word.loremIpsumParagraph(
            faker.numbers.intRange(1, 4),
            faker.numbers.intRange(1, 4),
            faker.numbers.intRange(4, 16),
            '\n\n',
        ),
        'tags': Array.from({length: faker.numbers.intRange(1, 4)}, () => faker.word.loremIpsumWord()),
        'localAlignment': faker.numbers.intRange(1, 42),
        'trail': false,
        'anonymous': false
    });
}

export function randomTiles(count) {
    const tiles = []

    for (let i = 0; i < count; i++) {
        const zoom = faker.numbers.intRange(10, 14);

        const tileN = Math.pow(2, zoom);
        const xMin = Math.floor((DACH_SOUTH_WEST.lng + 180) / 360 * tileN);
        const xMax = Math.floor((DACH_NORTH_EAST.lng + 180) / 360 * tileN);
        const radMin = DACH_SOUTH_WEST.lat * Math.PI / 180;
        const radMax = DACH_NORTH_EAST.lat * Math.PI / 180;
        const yMax = Math.floor((1 - Math.log(Math.tan(radMin) + 1 / Math.cos(radMin)) / Math.PI) / 2 * tileN);
        const yMin = Math.floor((1 - Math.log(Math.tan(radMax) + 1 / Math.cos(radMax)) / Math.PI) / 2 * tileN);

        const x = faker.numbers.intRange(xMin, xMax);
        const y = faker.numbers.intRange(yMin, yMax);

        tiles.push(['GET', `/${zoom}/${x}/${y}.pbf`])
    }

    return tiles;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// BUILDER
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
export function SeedFilter() {
    const filter = {
        'skip': 0,
        'limit': 10,
    }

    this.setBounds = function () {
        filter['bounds'] = {
            '_sw': SOUTH_WEST,
            '_ne': NORTH_EAST
        };
        return this;
    }

    this.setSort = function (sort) {
        filter['sort'] = sort;
        return this;
    }

    this.build = function () {
        return JSON.stringify(filter);
    }
}
