import React, { useState, useEffect, useRef } from 'react';
import { Play, Pause, Volume2, VolumeX, Repeat, Heart, Search, Home, Library, Clock, Plus, Edit2, Trash2, X, SkipBack, SkipForward, Shuffle, MoreHorizontal, Save, ChevronLeft, Loader } from 'lucide-react';
import { GetParentResourceName } from './hooks/useResource';
import { useLocale } from './hooks/useLocale';
import Swal from 'sweetalert2';
import './App.css'

const App = () => {
  const [visible, setVisible] = useState(false);
  const [currentTab, setCurrentTab] = useState('home');
  const [searchQuery, setSearchQuery] = useState('');
  const [searchResults, setSearchResults] = useState([]);
  const [playlists, setPlaylists] = useState([]);
  const [likedSongs, setLikedSongs] = useState([]);
  const [history, setHistory] = useState([]);
  const [currentUrl, setCurrentUrl] = useState('');
  const [currentSongName, setCurrentSongName] = useState('');
  const [currentSongImage, setCurrentSongImage] = useState('');
  const [currentSongAuthor, setCurrentSongAuthor] = useState('');
  const [volume, setVolume] = useState(20);
  const [isPlaying, setIsPlaying] = useState(false);
  const [isLooped, setIsLooped] = useState(false);
  const [currentTime, setCurrentTime] = useState(0);
  const [totalTime, setTotalTime] = useState(0);
  const [isLiked, setIsLiked] = useState(false);
  const [selectedPlaylist, setSelectedPlaylist] = useState(null);
  const [showVolumeSlider, setShowVolumeSlider] = useState(false);
  const [editingPlaylist, setEditingPlaylist] = useState(null);
  const [playlistName, setPlaylistName] = useState('');
  const [playlistImage, setPlaylistImage] = useState('');
  const [showAddToPlaylist, setShowAddToPlaylist] = useState(false);
  const [selectedSongForPlaylist, setSelectedSongForPlaylist] = useState(null);
  const [showCreatePlaylist, setShowCreatePlaylist] = useState(false);
  const [newPlaylistName, setNewPlaylistName] = useState('');
  const [newPlaylistImage, setNewPlaylistImage] = useState('');
  const [isSearching, setIsSearching] = useState(false);
  const [isLoadingSong, setIsLoadingSong] = useState(false);
  const [loadingSongId, setLoadingSongId] = useState(null);
  const [localeData, setLocaleData] = useState(null);
  const t = useLocale(localeData);
  const renderMusicImage = (imageUrl, altText = 'Music') => {
    if (imageUrl && imageUrl.trim() !== '') {
      return (
        <img
          src={imageUrl}
          alt={altText}
          onError={(e) => {
            e.target.style.display = 'none';
            if (e.target.nextSibling) e.target.nextSibling.style.display = 'flex';
          }}
        />
      );
    }
    return null;
  };

  useEffect(() => {
    const handleMessage = (event) => {
      const data = event.data;

      switch (data.action) {
        case 'setVisible':
          setVisible(data.data);
          if (data.data) {
            fetchInitialData();
          }
          break;
        case 'setLocale':
          if (data.locale && typeof data.locale === 'object') {
            setLocaleData(data.locale);
          }
          break;
        case 'changevidname':
          setCurrentUrl(data.text || '');
          break;
        case 'changeMusicVolume':
          setVolume(data.volume);
          break;
        case 'changeMusicLoop':
          setIsLooped(data.loop);
          break;
        case 'TimeVid':
          setCurrentTime(data.played);
          setTotalTime(data.total);
          break;
        case 'resSearchMusic':
          setSearchResults(data.searchList || []);
          setIsSearching(false);
          break;
        case 'resPlaylists':
          setPlaylists(JSON.parse(data.playlist || '[]'));
          break;
        case 'resLikeList':
          setLikedSongs(JSON.parse(data.listLike || '[]'));
          break;
        case 'resHistory':
          setHistory(JSON.parse(data.listLike || '[]'));
          break;
        case 'footerLike':
          setIsLiked(data.value);
          break;
        case 'showLikeMusic':
          setIsLiked(true);
          break;
        case 'remLikeMusic':
          setIsLiked(false);
          break;
        case 'musicUrlReceived':
          setCurrentSongName(data.name);
          setCurrentUrl(data.url);
          setCurrentSongImage(data.imageUrl || '');
          setCurrentSongAuthor(data.author || 'Central');
          setIsPlaying(true);
          setIsLoadingSong(false);
          setLoadingSongId(null);
          break;
      }
    };

    window.addEventListener('message', handleMessage);
    return () => window.removeEventListener('message', handleMessage);
  }, []);

  const sendNUI = (action, data = {}) => {
    fetch(`https://${GetParentResourceName()}/action`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ action, ...data })
    });
  };

  const fetchInitialData = () => {
    sendNUI('reqPlaylists', {});
    sendNUI('reqLikeList', {});
    sendNUI('reqHistory', {});
  };

  const handleClose = () => {
    setVisible(false);
    fetch(`https://${GetParentResourceName()}/hideFrame`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({})
    });
  };
  const handleSearch = () => {
    if (searchQuery.trim()) {
      setIsSearching(true);
      setSearchResults([]);
      sendNUI('searchMusic', { musicQuery: searchQuery });
      setCurrentTab('search');
    }
  };

  const handlePlayUrl = (musicId, name, imageUrl, author) => {
    setIsLoadingSong(true);
    setLoadingSongId(musicId);
    sendNUI('requestMusicUrl', {
      musicId: musicId,
      name: name,
      imageUrl: imageUrl,
      author: author
    });
  };

  const togglePlayPause = () => {
    sendNUI(isPlaying ? 'pause' : 'play', {});
    setIsPlaying(!isPlaying);
  };

  const handleVolumeChange = (e) => {
    const newVolume = parseInt(e.target.value);
    setVolume(newVolume);
    sendNUI('volume', { value: newVolume });
  };

  const toggleLoop = () => {
    sendNUI('loop', {});
  };

  const toggleLike = () => {
    if (isLiked) {
      sendNUI('remLike', { url_id: currentUrl });
    } else {
      sendNUI('liked', {
        url_id: currentUrl,
        name: currentSongName || 'Current Song',
        newIdBd: Date.now()
      });
    }
  };

  const handleTimeSeek = (e) => {
    const newTime = parseInt(e.target.value);
    setCurrentTime(newTime);
    sendNUI('setNewTime', { newTime });
  };

  const openCreatePlaylistModal = () => {
    setNewPlaylistName('');
    setNewPlaylistImage('https://images.unsplash.com/photo-1494232410401-ad00d5433cfa?ixlib=rb-4.0.3&auto=format&fit=crop&w=1170&q=80');
    setShowCreatePlaylist(true);
  };

  const createPlaylist = () => {
    if (newPlaylistName.trim()) {
      sendNUI('createPlaylist', {
        name: newPlaylistName,
        url_img: newPlaylistImage || 'https://images.unsplash.com/photo-1494232410401-ad00d5433cfa?ixlib=rb-4.0.3&auto=format&fit=crop&w=1170&q=80'
      });
      setTimeout(() => {
        sendNUI('reqPlaylists', {});
      }, 500);
      setShowCreatePlaylist(false);
      setNewPlaylistName('');
      setNewPlaylistImage('');
    }
  };

  const deletePlaylist = (id) => {
    Swal.fire({
      title: t('ui.modals.deletePlaylist.title'),
      text: t('ui.modals.deletePlaylist.text'),
      icon: 'warning',
      showCancelButton: true,
      confirmButtonText: t('ui.modals.deletePlaylist.confirmButton'),
      cancelButtonText: t('ui.modals.deletePlaylist.cancelButton'),
      background: '#121212',
      color: '#ffffff',
      confirmButtonColor: '#333333',
      cancelButtonColor: '#333333',
      reverseButtons: true
    }).then((result) => {
      if (result.isConfirmed) {
        sendNUI('deletePlaylist', { id });

        setTimeout(() => {
          sendNUI('reqPlaylists', {});

          if (selectedPlaylist && selectedPlaylist.id === id) {
            setSelectedPlaylist(null);
            setCurrentTab('library');
          }
        }, 500);

        Swal.fire({
          title: t('ui.modals.deletePlaylist.successTitle'),
          text: t('ui.modals.deletePlaylist.successText'),
          icon: 'success',
          timer: 1500,
          showConfirmButton: false,
          background: '#121212',
          color: '#ffffff'
        });
      }
    });
  };

  const startEditPlaylist = (playlist) => {
    setEditingPlaylist(playlist.id);
    setPlaylistName(playlist.name);
    setPlaylistImage(playlist.url_img);
  };

  const savePlaylistEdit = (id) => {
    if (playlistName.trim()) {
      sendNUI('editPlaylist', {
        id: id,
        name: playlistName,
        url_img: playlistImage
      });

      setTimeout(() => {
        sendNUI('reqPlaylists', {});
        setEditingPlaylist(null);
        setPlaylistName('');
        setPlaylistImage('');
      }, 500);
    }
  };

  const cancelEdit = () => {
    setEditingPlaylist(null);
    setPlaylistName('');
    setPlaylistImage('');
  };

  const openAddToPlaylist = (song) => {
    setSelectedSongForPlaylist(song);
    setShowAddToPlaylist(true);
  };

  const addSongToPlaylist = (playlistId) => {
    if (selectedSongForPlaylist) {
      sendNUI('addToPlaylist', {
        playlistId: playlistId,
        url_id: selectedSongForPlaylist.url_id || selectedSongForPlaylist.id,
        name: selectedSongForPlaylist.name,
        id: selectedSongForPlaylist.id || Date.now(),
        image_url: selectedSongForPlaylist.image_url || 'https://via.placeholder.com/40'
      });

      setTimeout(() => {
        sendNUI('reqPlaylists', {});
        setShowAddToPlaylist(false);
        setSelectedSongForPlaylist(null);
      }, 500);
    }
  };

  const removeSongFromPlaylist = (musicId, playlistId) => {
    sendNUI('removeToPlaylist', {
      id: musicId,
      playlistId: playlistId
    });

    setTimeout(() => {
      sendNUI('reqPlaylists', {});
    }, 500);
  };

  const formatTime = (seconds) => {
    const mins = Math.floor(seconds / 60);
    const secs = Math.floor(seconds % 60);
    return `${mins}:${secs.toString().padStart(2, '0')}`;
  };

  if (!visible) return null;

  return (
    <div className="centralfy-wrapper">
      <div className="centralfy-container">
        <div className="sidebar">
          <div className="sidebar-header">
            <div className="logo">
              <img src="https://cdn.centralcity.gg/utils/central2025.png" alt="CentralLogo" width={'120px'} />
            </div>
          </div>

          <nav className="sidebar-nav">
            <button
              className={currentTab === 'home' ? 'nav-item active' : 'nav-item'}
              onClick={() => setCurrentTab('home')}
            >
              <Home size={24} />
              <span>{t('ui.nav.home')}</span>
            </button>

            <button
              className={currentTab === 'search' ? 'nav-item active' : 'nav-item'}
              onClick={() => setCurrentTab('search')}
            >
              <Search size={24} />
              <span>{t('ui.nav.search')}</span>
            </button>

            <button
              className={currentTab === 'library' ? 'nav-item active' : 'nav-item'}
              onClick={() => setCurrentTab('library')}
            >
              <Library size={24} />
              <span>{t('ui.nav.library')}</span>
            </button>
          </nav>

          <div className="sidebar-playlists">
            <button className="create-playlist" onClick={openCreatePlaylistModal}>
              <Plus size={20} />
              <span>{t('ui.sidebar.createPlaylist')}</span>
            </button>

            <button
              className={currentTab === 'liked' ? 'nav-item liked-songs active' : 'nav-item liked-songs'}
              onClick={() => setCurrentTab('liked')}
            >
              <div className="liked-icon">
                <Heart size={16} fill="white" />
              </div>
              <span>{t('ui.sidebar.likedSongs')}</span>
            </button>

            <div className="playlist-list">
              {playlists.map((playlist) => (
                <button
                  key={playlist.id}
                  className="playlist-item"
                  onClick={() => {
                    setSelectedPlaylist(playlist);
                    setCurrentTab('playlist-view');
                  }}
                >
                  {playlist.name}
                </button>
              ))}
            </div>
          </div>
        </div>
        <div className="main-content">
          <div className="top-bar">
            <div className="search-container">
              <Search size={20} className="search-icon" />
              <input
                type="text"
                placeholder={t('ui.search.placeholder')}
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                onKeyPress={(e) => e.key === 'Enter' && handleSearch()}
              />
              {isSearching && (
                <div className="search-loading">
                  <Loader className="spinner" size={16} />
                </div>
              )}
            </div>
            <button className="close-button" onClick={handleClose}>
              <X size={24} />
            </button>
          </div>

          <div className="content-area">

            {currentTab === 'home' && (
              <div className="home-view">
                <h1 className="greeting">{t('ui.home.greeting')}</h1>

                {history.length > 0 && (
                  <section className="content-section">
                    <h2>{t('ui.home.recentlyPlayed')}</h2>
                    <div className="quick-play-grid">
                      {history.slice(0, 6).map((song, index) => (
                        <div
                          key={index}
                          className="quick-play-card"
                          onClick={() => handlePlayUrl(song.id, song.name, song.image_url, song.author)}
                        >
                          <div className="quick-play-image">
                            {renderMusicImage(song.image_url, song.name)}
                            <div className="music-placeholder" style={{ display: song.image_url ? 'none' : 'flex' }}>♪</div>
                          </div>
                          <span className="quick-play-title">{song.name}</span>
                          <div className="quick-play-overlay">
                            {isLoadingSong && loadingSongId === song.id ? (
                              <Loader className="spinner" size={24} />
                            ) : (
                              <Play size={24} fill="black" />
                            )}
                          </div>
                        </div>
                      ))}
                    </div>
                  </section>
                )}

                {playlists.length > 0 && (
                  <section className="content-section">
                    <div className="section-header">
                      <h2>{t('ui.home.yourPlaylists')}</h2>
                    </div>
                    <div className="card-grid">
                      {playlists.map((playlist) => (
                        <div key={playlist.id} className="playlist-card">
                          <div className="card-image">
                            <img src={playlist.url_img} alt={playlist.name} />
                            <button className="card-play-button" onClick={() => {
                              setSelectedPlaylist(playlist);
                              setCurrentTab('playlist-view');
                            }}>
                              <Play size={20} fill="black" />
                            </button>
                          </div>
                          <h3>{playlist.name}</h3>
                          <p>{playlist.music_playlist?.length || 0} {t('ui.playlistView.songCount')}</p>
                        </div>
                      ))}
                    </div>
                  </section>
                )}
              </div>
            )}

            {currentTab === 'search' && (
              <div className="search-view">
                <h1>{t('ui.search.resultsTitle')}</h1>
                {isSearching ? (
                  <div className="loading-container">
                    <div className="loading-spinner">
                      <Loader className="spinner-large" size={48} />
                    </div>
                    <p>{t('ui.search.searching')}</p>
                  </div>
                ) : searchResults.length > 0 ? (
                  <div className="search-results">
                    <div className="track-list">
                      {searchResults.map((result, index) => (
                        <div key={index} className="track-item">
                          <div className="track-number" onClick={() => handlePlayUrl(result._id, result.name, result.image_url, result.author)}>
                            {isLoadingSong && loadingSongId === result._id ? (
                              <Loader className="spinner-small" size={14} />
                            ) : (
                              index + 1
                            )}
                          </div>
                          <div className="track-image" onClick={() => handlePlayUrl(result._id, result.name, result.image_url, result.author)}>
                            {renderMusicImage(result.image_url, result.name)}
                            <div className="music-placeholder" style={{ display: result.image_url ? 'none' : 'flex' }}>♪</div>
                          </div>
                          <div className="track-info" onClick={() => handlePlayUrl(result._id, result.name, result.image_url, result.author)}>
                            <div className="track-title">{result.name}</div>
                            <div className="track-artist">{result.author || t('ui.search.unknownArtist')}</div>
                          </div>
                          <button
                            className="add-to-playlist-btn"
                            onClick={() => openAddToPlaylist({ id: result._id, name: result.name, image_url: result.image_url })}
                          >
                            <Plus size={16} />
                          </button>
                        </div>
                      ))}
                    </div>
                    </div>
                  ) : (
                  <div className="search-empty">
                    <Search size={80} />
                    <p>{t('ui.search.emptyMessage')}</p>
                  </div>
                )}
              </div>
            )}

            {currentTab === 'library' && (
              <div className="library-view">
                <h1>{t('ui.library.title')}</h1>
                <div className="card-grid">
                  {playlists.map((playlist) => (
                    <div key={playlist.id} className="playlist-card">
                      {editingPlaylist === playlist.id ? (
                        <div className="edit-playlist-form">
                          <input
                            type="text"
                            value={playlistName}
                            onChange={(e) => setPlaylistName(e.target.value)}
                            placeholder={t('ui.modals.editPlaylist.namePlaceholder')}
                            className="edit-input"
                          />
                          <input
                            type="text"
                            value={playlistImage}
                            onChange={(e) => setPlaylistImage(e.target.value)}
                            placeholder={t('ui.modals.editPlaylist.imagePlaceholder')}
                            className="edit-input"
                          />
                          <div className="edit-actions">
                            <button onClick={() => savePlaylistEdit(playlist.id)} className="save-btn">
                              <Save size={16} /> {t('ui.modals.editPlaylist.saveButton')}
                            </button>
                            <button onClick={cancelEdit} className="cancel-btn">
                              <X size={16} /> {t('ui.modals.editPlaylist.cancelButton')}
                            </button>
                          </div>
                        </div>
                      ) : (
                        <>
                          <div className="card-image">
                            <img src={playlist.url_img} alt={playlist.name} />
                            <button className="card-play-button" onClick={() => {
                              setSelectedPlaylist(playlist);
                              setCurrentTab('playlist-view');
                            }}>
                              <Play size={20} fill="black" />
                            </button>
                          </div>
                          <h3>{playlist.name}</h3>
                          <p>{playlist.music_playlist?.length || 0} {t('ui.playlistView.songCount')}</p>
                          <div className="card-actions">
                            <button onClick={() => startEditPlaylist(playlist)}>
                              <Edit2 size={16} />
                            </button>
                            <button onClick={() => deletePlaylist(playlist.id)}>
                              <Trash2 size={16} />
                            </button>
                          </div>
                        </>
                      )}
                    </div>
                  ))}
                </div>
              </div>
            )}

            {currentTab === 'liked' && (
              <div className="liked-view">
                <div className="playlist-header">
                  <div className="playlist-cover liked-cover">
                    <Heart size={60} fill="white" />
                  </div>
                  <div className="playlist-details">
                    <span className="playlist-type">{t('ui.playlistView.playlistLabel')}</span>
                    <h1>{t('ui.liked.title')}</h1>
                    <p>{likedSongs.length} {t('ui.liked.songCount')}</p>
                  </div>
                </div>
                <div className="playlist-content">
                  <div className="track-list">
                    {likedSongs.map((song, index) => (
                      <div key={index} className="track-item" onClick={() => handlePlayUrl(song.id, song.name, song.image_url, song.author)}>
                        <div className="track-number">
                          {isLoadingSong && loadingSongId === song.id ? (
                            <Loader className="spinner-small" size={14} />
                          ) : (
                            index + 1
                          )}
                        </div>
                        <div className="track-image">
                          {renderMusicImage(song.image_url, song.name)}
                          <div className="music-placeholder" style={{ display: song.image_url ? 'none' : 'flex' }}>♪</div>
                        </div>
                        <div className="track-info">
                          <div className="track-title">{song.name}</div>
                        </div>
                      </div>
                    ))}
                  </div>
                </div>
              </div>
            )}

            {currentTab === 'playlist-view' && selectedPlaylist && (
              <div className="playlist-view">
                <button className="back-button" onClick={() => setCurrentTab('library')}>
                  <ChevronLeft size={24} /> {t('ui.playlistView.back')}
                </button>
                <div className="playlist-header">
                  <div className="playlist-cover">
                    <img src={selectedPlaylist.url_img} alt={selectedPlaylist.name} />
                  </div>
                  <div className="playlist-details">
                    <span className="playlist-type">{t('ui.playlistView.playlistLabel')}</span>
                    <h1>{selectedPlaylist.name}</h1>
                    <p>{selectedPlaylist.music_playlist?.length || 0} {t('ui.playlistView.songCount')}</p>
                  </div>
                </div>
                <div className="playlist-content">
                  <div className="track-list">
                    {selectedPlaylist.music_playlist && selectedPlaylist.music_playlist.map((song, index) => (
                      <div key={index} className="track-item">
                        <div className="track-number" onClick={() => handlePlayUrl(song.id, song.name, song.image_url, song.author)}>
                          {isLoadingSong && loadingSongId === song.id ? (
                            <Loader className="spinner-small" size={14} />
                          ) : (
                            index + 1
                          )}
                        </div>
                        <div className="track-image" onClick={() => handlePlayUrl(song.id, song.name, song.image_url, song.author)}>
                          {renderMusicImage(song.image_url, song.name)}
                          <div className="music-placeholder" style={{ display: song.image_url ? 'none' : 'flex' }}>♪</div>
                        </div>
                        <div className="track-info" onClick={() => handlePlayUrl(song.id, song.name, song.image_url, song.author)}>
                          <div className="track-title">{song.name}</div>
                        </div>
                        <button
                          className="remove-from-playlist-btn"
                          onClick={() => removeSongFromPlaylist(song.id, selectedPlaylist.id)}
                        >
                          <X size={16} />
                        </button>
                      </div>
                    ))}
                  </div>
                </div>
              </div>
            )}

          </div>
        </div>
      </div>

      <div className="player-bar">
        <div className="player-left">
          <div className="now-playing-image">
            {isLoadingSong && !currentSongImage ? (
              <div className="music-placeholder">
                <Loader className="spinner-small" size={20} />
              </div>
            ) : (
              <>
                {renderMusicImage(currentSongImage, currentSongName)}
                <div className="music-placeholder" style={{ display: currentSongImage ? 'none' : 'flex' }}>♪</div>
              </>
            )}
          </div>
          <div className="now-playing-info">
            <div className="now-playing-title">
              {currentSongName || t('ui.player.selectSong')}
            </div>
            <div className="now-playing-artist">
              {currentSongAuthor || t('ui.player.defaultArtist')}
            </div>
          </div>
          <button className={isLiked ? 'icon-button liked' : 'icon-button'} onClick={toggleLike}>
            <Heart size={16} fill={isLiked ? 'currentColor' : 'none'} />
          </button>
        </div>

        <div className="player-center">
          <div className="player-controls">
            <button className="control-button">
              <Shuffle size={16} />
            </button>
            <button className="control-button">
              <SkipBack size={20} />
            </button>
            <button className="play-button" onClick={togglePlayPause}>
              {isPlaying ? <Pause size={20} fill="white" /> : <Play size={20} fill="white" />}
            </button>
            <button className="control-button">
              <SkipForward size={20} />
            </button>
            <button className={isLooped ? 'control-button active' : 'control-button'} onClick={toggleLoop}>
              <Repeat size={16} />
            </button>
          </div>
          <div className="playback-bar">
            <span className="time-label">{formatTime(currentTime)}</span>
            <input
              type="range"
              min="0"
              max={totalTime || 100}
              value={currentTime}
              onChange={handleTimeSeek}
              className="progress-bar"
            />
            <span className="time-label">{formatTime(totalTime)}</span>
          </div>
        </div>

        <div className="player-right">
          <div className="volume-control">
            <button
              className="icon-button"
              onMouseEnter={() => setShowVolumeSlider(true)}
              onMouseLeave={() => setShowVolumeSlider(false)}
            >
              {volume === 0 ? <VolumeX size={16} /> : <Volume2 size={16} />}
            </button>
            {showVolumeSlider && (
              <div
                className="volume-slider-container"
                onMouseEnter={() => setShowVolumeSlider(true)}
                onMouseLeave={() => setShowVolumeSlider(false)}
              >
                <input
                  type="range"
                  min="0"
                  max="100"
                  value={volume}
                  onChange={handleVolumeChange}
                  className="volume-slider"
                  orient="vertical"
                />
                <span className="volume-label">{volume}%</span>
              </div>
            )}
          </div>
        </div>
      </div>
 
      {showCreatePlaylist && (
        <div className="modal-overlay" onClick={() => setShowCreatePlaylist(false)}>
          <div className="modal-content" onClick={(e) => e.stopPropagation()}>
            <div className="modal-header">
              <h2>{t('ui.modals.createPlaylist.title')}</h2>
              <button onClick={() => setShowCreatePlaylist(false)}>
                <X size={24} />
              </button>
            </div>
            <div className="modal-body">
              <div className="create-playlist-form">
                <div className="form-group">
                  <label>{t('ui.modals.createPlaylist.nameLabel')}</label>
                  <input
                    type="text"
                    value={newPlaylistName}
                    onChange={(e) => setNewPlaylistName(e.target.value)}
                    placeholder={t('ui.modals.createPlaylist.namePlaceholder')}
                    className="edit-input"
                    autoFocus
                  />
                </div>
                <div className="form-group">
                  <label>{t('ui.modals.createPlaylist.imageLabel')}</label>
                  <input
                    type="text"
                    value={newPlaylistImage}
                    onChange={(e) => setNewPlaylistImage(e.target.value)}
                    placeholder={t('ui.modals.createPlaylist.imagePlaceholder')}
                    className="edit-input"
                  />
                </div>
                {newPlaylistImage && (
                  <div className="image-preview">
                    <img src={newPlaylistImage} alt="Preview" onError={(e) => e.target.style.display = 'none'} />
                  </div>
                )}
                <button onClick={createPlaylist} className="create-btn" disabled={!newPlaylistName.trim()}>
                  <Plus size={16} /> {t('ui.modals.createPlaylist.createButton')}
                </button>
              </div>
            </div>
          </div>
        </div>
      )}

      {showAddToPlaylist && (
        <div className="modal-overlay" onClick={() => setShowAddToPlaylist(false)}>
          <div className="modal-content" onClick={(e) => e.stopPropagation()}>
            <div className="modal-header">
              <h2>{t('ui.modals.addToPlaylist.title')}</h2>
              <button onClick={() => setShowAddToPlaylist(false)}>
                <X size={24} />
              </button>
            </div>
            <div className="modal-body">
              {playlists.map((playlist) => (
                <div
                  key={playlist.id}
                  className="playlist-option"
                  onClick={() => addSongToPlaylist(playlist.id)}
                >
                  <img src={playlist.url_img} alt={playlist.name} />
                  <span>{playlist.name}</span>
                </div>
              ))}
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

export default App;